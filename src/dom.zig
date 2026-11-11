const std = @import("std");
const Allocator = std.mem.Allocator;
const node = @import("node.zig");
const View = @import("view.zig").View;
const Declaration = node.Node;
const Snapshot = node.Snapshot;

/// Backend-independent reconciliation of View snapshots into retained native
/// widgets, like CPPUI's dom.hpp and PUI's dom.py. Widgets live in a backend
/// (see src/lvgl/backend.zig), which provides:
///
/// - `Widget`: retained native state for one physical node.
/// - `Parent`: a native insertion point. `rootParent()` returns the top one and
///   `parentOf(*Widget)` a container's.
/// - `Native` and `native(*Widget)`: the handle returned by `find()`.
/// - `Layout`: per-update storage for a container, prepared before anything is
///   committed; `prepareLayout(allocator, declaration, physical_children)` and
///   `freeLayout(allocator, layout)`.
/// - `create(mounted, parent) !Widget` and `destroy(allocator, mounted)`.
/// - `update(allocator, *Widget, declaration, ?Layout)`, which takes ownership
///   of the layout; `place(parent, parent_declaration, child, index)` for each
///   physical child in order; then `finish(*Widget, declaration)`.
///
/// Native callbacks use `busy`, `dispatch_depth`, `report()` and
/// `nativeDeleted()` to stay outside reconciliation.
pub fn Dom(comptime Backend: type) type {
    return struct {
        const Self = @This();

        pub const Mounted = struct {
            dom: *Self,
            owner: *View,
            view: ?*View = null,
            widget: ?Backend.Widget = null,
            declaration: *Declaration,
            children: std.ArrayListUnmanaged(*Mounted) = std.ArrayListUnmanaged(*Mounted).empty,
        };

        const Plan = struct {
            mounted: *Mounted,
            declaration: *Declaration,
            is_new: bool,
            children: []*Plan = &.{},
            prepared: usize = 0,
            layout: ?Backend.Layout = null,
            next_snapshot: ?*Snapshot = null,
        };

        allocator: Allocator,
        view: View,
        root: ?*Mounted = null,
        busy: bool = false,
        dispatch_depth: usize = 0,
        event_error: ?anyerror = null,
        render_count: usize = 0,

        pub fn init(allocator: Allocator, model: anytype) Self {
            return .{ .allocator = allocator, .view = View.init(allocator, @import("view.zig").Content.init(model)) };
        }
        pub fn deinit(self: *Self) void {
            std.debug.assert(!self.busy and self.dispatch_depth == 0);
            self.busy = true;
            if (self.root) |root| self.destroyMounted(root);
            self.view.deinit();
        }
        pub fn invalidate(self: *Self) void {
            self.view.invalidate();
        }
        /// Record a callback or binding error for the next flush() and keep the
        /// owning View dirty so it restores the model's value.
        pub fn report(self: *Self, mounted: *Mounted, err: anyerror) void {
            self.event_error = err;
            mounted.owner.invalidate();
        }
        /// The native widget was deleted outside ZUI; remount it on flush.
        pub fn nativeDeleted(self: *Self, mounted: *Mounted) void {
            if (mounted.widget) |*widget| Backend.forget(self.allocator, widget);
            mounted.widget = null;
            mounted.owner.invalidate();
        }

        pub fn flush(self: *Self) !void {
            if (self.busy or self.dispatch_depth != 0) return error.ReentrantFlush;
            if (self.event_error) |err| {
                self.event_error = null;
                return err;
            }
            if (!self.view.observer.dirty and !hasDirtyView(self.root)) return;
            self.busy = true;
            defer self.busy = false;
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const next = if (self.view.observer.dirty) try self.view.prepare() else null;
            errdefer if (next) |snapshot| snapshot.destroy();
            const snapshot = next orelse self.view.snapshot.?;
            const plan = try self.prepare(self.root, &snapshot.root, Backend.rootParent(), &self.view, arena.allocator());
            errdefer self.discard(plan);
            // Several newly prepared Views may subscribe to the same Signal. Reserve
            // for all of them before any observer commits into its shared list.
            const count = countUpdates(plan) + @as(usize, if (next != null) 1 else 0);
            if (next) |pending| try reserveSignals(pending, count);
            try reserveUpdates(plan, count);
            self.commit(plan);
            if (self.root) |old_root| {
                if (old_root != plan.mounted) self.destroyMounted(old_root);
            }
            self.root = plan.mounted;
            if (next) |pending| self.view.commit(pending);
            self.render_count += 1;
        }
        fn hasDirtyView(mounted: ?*Mounted) bool {
            const current = mounted orelse return false;
            if (current.view) |view| if (view.observer.dirty) return true;
            for (current.children.items) |child| if (hasDirtyView(child)) return true;
            return false;
        }
        fn countUpdates(plan: *Plan) usize {
            var count: usize = if (plan.next_snapshot != null) 1 else 0;
            for (plan.children) |child| count += countUpdates(child);
            return count;
        }
        fn reserveSignals(snapshot: *Snapshot, count: usize) !void {
            for (snapshot.dependencies.items) |signal|
                try signal.observers.ensureUnusedCapacity(signal.allocator, count);
        }
        fn reserveUpdates(plan: *Plan, count: usize) !void {
            if (plan.next_snapshot) |snapshot| try reserveSignals(snapshot, count);
            for (plan.children) |child| try reserveUpdates(child, count);
        }

        /// A borrowed retained View, valid until this subtree is removed.
        pub fn findView(self: *Self, name: []const u8) ?*View {
            return if (self.root) |root| findViewIn(root, name) else null;
        }
        fn findViewIn(mounted: *Mounted, name: []const u8) ?*View {
            if (mounted.declaration.options.id) |own| {
                if (std.mem.eql(u8, name, own)) if (mounted.view) |view| return view;
            }
            for (mounted.children.items) |child| {
                if (findViewIn(child, name)) |view| return view;
            }
            return null;
        }
        /// Returns the first depth-first matching id. This handle is borrowed and
        /// invalid after removal. Native deletion is observed and remounted on flush.
        pub fn find(self: *Self, name: []const u8) ?Backend.Native {
            return if (self.root) |root| findIn(root, name) else null;
        }
        fn findIn(mounted: *Mounted, name: []const u8) ?Backend.Native {
            if (mounted.declaration.options.id) |own| {
                if (std.mem.eql(u8, name, own)) if (mounted.widget) |*widget| return Backend.native(widget);
            }
            for (mounted.children.items) |child| {
                if (findIn(child, name)) |found| return found;
            }
            return null;
        }

        fn createMounted(self: *Self, declaration: *Declaration, parent: Backend.Parent, owner: *View) !*Mounted {
            const mounted = try self.allocator.create(Mounted);
            errdefer self.allocator.destroy(mounted);
            mounted.* = .{ .dom = self, .owner = owner, .declaration = declaration };
            if (declaration.kind == .view) {
                const view = try self.allocator.create(View);
                view.* = View.init(self.allocator, declaration.content.?);
                mounted.view = view;
                return mounted;
            }
            mounted.widget = try Backend.create(mounted, parent);
            return mounted;
        }

        fn prepare(self: *Self, previous: ?*Mounted, declaration: *Declaration, parent: Backend.Parent, owner: *View, arena: Allocator) anyerror!*Plan {
            const old = if (previous) |current| (if (current.widget != null or current.view != null) current else null) else null;
            const plan = try arena.create(Plan);
            plan.* = .{
                .mounted = old orelse try self.createMounted(declaration, parent, owner),
                .declaration = declaration,
                .is_new = old == null,
            };
            errdefer self.discard(plan);
            var children = declaration.children.items;
            const child_owner = plan.mounted.view orelse owner;
            if (plan.mounted.view) |view| {
                if (view.observer.dirty) plan.next_snapshot = try view.prepare();
                const snapshot = plan.next_snapshot orelse view.snapshot.?;
                children = snapshot.root.children.items;
            }
            const child_parent = if (plan.mounted.widget) |*widget| Backend.parentOf(widget) else parent;
            plan.children = try arena.alloc(*Plan, children.len);
            try plan.mounted.children.ensureTotalCapacity(self.allocator, children.len);
            for (children, 0..) |child, index| {
                var match: ?*Mounted = null;
                if (old) |current| {
                    for (current.children.items, 0..) |candidate, old_index| {
                        if (node.sameIdentity(candidate.declaration, child, old_index, index)) {
                            match = candidate;
                            break;
                        }
                    }
                }
                plan.children[index] = try self.prepare(match, child, child_parent, child_owner, arena);
                plan.prepared += 1;
            }
            const child_count = physicalChildCount(plan);
            if (declaration.kind == .splitter and child_count != 2) return error.InvalidPaneCount;
            if (plan.mounted.widget != null)
                plan.layout = try Backend.prepareLayout(self.allocator, declaration, child_count);
            return plan;
        }
        fn physicalChildCount(plan: *Plan) usize {
            var count: usize = 0;
            for (plan.children) |child|
                count += if (child.mounted.view != null) physicalChildCount(child) else 1;
            return count;
        }

        fn discard(self: *Self, plan: *Plan) void {
            for (plan.children[0..plan.prepared]) |child| self.discard(child);
            if (plan.layout) |layout| Backend.freeLayout(self.allocator, layout);
            if (plan.next_snapshot) |snapshot| snapshot.destroy();
            if (plan.is_new) self.destroyMounted(plan.mounted);
        }
        fn destroyMounted(self: *Self, mounted: *Mounted) void {
            for (mounted.children.items) |child| self.destroyMounted(child);
            mounted.children.deinit(self.allocator);
            if (mounted.widget != null) Backend.destroy(self.allocator, mounted);
            if (mounted.view) |view| {
                view.deinit();
                self.allocator.destroy(view);
            }
            self.allocator.destroy(mounted);
        }

        fn commit(self: *Self, plan: *Plan) void {
            const mounted = plan.mounted;
            for (mounted.children.items) |child| {
                var retained = false;
                for (plan.children) |next| {
                    if (next.mounted == child) {
                        retained = true;
                        break;
                    }
                }
                if (!retained) self.destroyMounted(child);
            }
            if (mounted.widget) |*widget| {
                Backend.update(self.allocator, widget, plan.declaration, plan.layout);
                plan.layout = null;
            }
            mounted.declaration = plan.declaration;
            mounted.children.clearRetainingCapacity();
            for (plan.children) |child| {
                self.commit(child);
                mounted.children.appendAssumeCapacity(child.mounted);
            }
            if (mounted.widget) |*widget| {
                var index: usize = 0;
                for (mounted.children.items) |child| placeChild(widget, plan.declaration, child, &index);
                Backend.finish(widget, plan.declaration);
            }
            if (plan.next_snapshot) |snapshot| mounted.view.?.commit(snapshot);
        }
        // Virtual Views contribute zero or more native children to their nearest
        // physical parent. They never add a native container of their own.
        fn placeChild(parent: *Backend.Widget, declaration: *const Declaration, child: *Mounted, index: *usize) void {
            if (child.view != null) {
                for (child.children.items) |nested| placeChild(parent, declaration, nested, index);
                return;
            }
            Backend.place(parent, declaration, &child.widget.?, index.*);
            index.* += 1;
        }
    };
}
