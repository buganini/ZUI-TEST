const std = @import("std");
pub const native = @import("c");
const c = native;
const core = @import("core");
pub const Builder = core.Builder;
pub const State = core.State;
pub const TextState = core.TextState;
pub const Binding = core.Binding;
pub const Signal = core.Signal;
pub const Options = core.Options;
pub const callback = core.callback;
const Allocator = std.mem.Allocator;
const Declaration = core.Declaration;

const Mounted = struct {
    app: *App,
    object: ?*c.lv_obj_t = null,
    label: ?*c.lv_obj_t = null,
    declaration: *Declaration,
    children: std.ArrayList(*Mounted) = .empty,
};

const Plan = struct {
    mounted: *Mounted,
    declaration: *Declaration,
    is_new: bool,
    children: []*Plan = &.{},
    prepared: usize = 0,
    columns: ?[*]const i32 = null,
    rows: ?[*]const i32 = null,
};

pub const AppOptions = struct {
    title: [:0]const u8 = "ZUI",
    width: i32 = 800,
    height: i32 = 600,
};

/// One owned SDL2/LVGL host, one reactive root. The model is borrowed and must
/// outlive the App. Component functions can compose builders under this root.
pub const App = struct {
    allocator: Allocator,
    host: *c.zui_host,
    context: *anyopaque,
    build_fn: *const fn (*anyopaque, *Builder) anyerror!void,
    observer: core.Observer,
    snapshot: ?*core.Snapshot = null,
    root: ?*Mounted = null,
    busy: bool = false,
    dispatch_depth: usize = 0,
    event_error: ?anyerror = null,
    render_count: usize = 0,

    pub fn create(allocator: Allocator, model: anytype, options: AppOptions) !*App {
        if (options.width <= 0 or options.height <= 0) return error.InvalidWindowSize;
        const T = @TypeOf(model);
        const self = try allocator.create(App);
        errdefer allocator.destroy(self);
        const host = c.zui_host_create(options.title, options.width, options.height) orelse return error.HostUnavailable;
        self.* = .{
            .allocator = allocator,
            .host = host,
            .context = model,
            .observer = .init(allocator),
            .build_fn = struct {
                fn build(raw: *anyopaque, ui: *Builder) !void {
                    const context: T = @ptrCast(@alignCast(raw));
                    try context.build(ui);
                }
            }.build,
        };
        return self;
    }

    /// Call after run()/pump() returns, never from a builder or native callback.
    pub fn destroy(self: *App) void {
        std.debug.assert(!self.busy and self.dispatch_depth == 0);
        self.busy = true;
        self.observer.deinit();
        if (self.root) |root| self.destroyMounted(root);
        if (self.snapshot) |snapshot| snapshot.destroy();
        c.zui_host_destroy(self.host);
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn invalidate(self: *App) void {
        self.observer.dirty = true;
    }
    pub fn requestQuit(self: *App) void {
        c.zui_host_request_close(self.host);
    }

    pub fn flush(self: *App) !void {
        if (self.busy or self.dispatch_depth != 0) return error.ReentrantFlush;
        if (self.event_error) |err| {
            self.event_error = null;
            return err;
        }
        if (!self.observer.dirty) return;
        self.busy = true;
        defer self.busy = false;
        const next = try core.Snapshot.create(self.allocator);
        errdefer next.destroy();
        {
            core.build_depth += 1;
            defer core.build_depth -= 1;
            var ui = next.builder();
            try self.build_fn(self.context, &ui);
        }
        try self.observer.prepare(next.dependencies.items);
        // New native objects are hidden until the whole plan is ready. Every
        // fallible Zig allocation occurs before commit mutates existing widgets.
        const plan = try self.prepare(self.root, &next.root, c.lv_screen_active().?, next.arena.allocator());
        self.commit(plan);
        if (self.root) |old_root| {
            if (old_root != plan.mounted) self.destroyMounted(old_root);
        }
        self.root = plan.mounted;
        self.observer.commit(next.dependencies.items);
        const previous = self.snapshot;
        self.snapshot = next;
        if (previous) |old| old.destroy();
        self.render_count += 1;
    }

    pub fn pump(self: *App) !bool {
        if (c.zui_host_closing(self.host)) return false;
        try self.flush();
        _ = c.zui_host_pump(self.host);
        if (c.zui_host_closing(self.host)) return false;
        try self.flush();
        return true;
    }
    pub fn run(self: *App) !void {
        while (try self.pump()) c.zui_host_delay(8);
    }

    /// Returns the first depth-first matching key. This pointer is borrowed and
    /// invalid after removal. Native deletion is observed and remounted on flush.
    pub fn find(self: *App, key: []const u8) ?*c.lv_obj_t {
        return if (self.root) |root| findIn(root, key) else null;
    }
    fn findIn(mounted: *Mounted, key: []const u8) ?*c.lv_obj_t {
        if (mounted.declaration.options.key) |own| {
            if (std.mem.eql(u8, key, own)) return mounted.object;
        }
        for (mounted.children.items) |child| {
            if (findIn(child, key)) |found| return found;
        }
        return null;
    }

    fn createMounted(self: *App, declaration: *Declaration, parent: *c.lv_obj_t) !*Mounted {
        const mounted = try self.allocator.create(Mounted);
        errdefer self.allocator.destroy(mounted);
        mounted.* = .{ .app = self, .declaration = declaration };
        const object = switch (declaration.kind) {
            .label => c.lv_label_create(parent),
            .button => c.lv_button_create(parent),
            .checkbox => c.lv_checkbox_create(parent),
            .text_field => c.lv_textarea_create(parent),
            else => c.lv_obj_create(parent),
        } orelse return error.NativeCreateFailed;
        errdefer c.lv_obj_delete(object);
        mounted.object = object;
        c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_HIDDEN);
        if (declaration.kind == .button)
            mounted.label = c.lv_label_create(object) orelse return error.NativeCreateFailed;
        if (declaration.kind == .text_field) c.lv_textarea_set_one_line(object, true);
        _ = c.lv_obj_add_event_cb(object, eventCallback, c.LV_EVENT_ALL, mounted);
        return mounted;
    }

    fn prepare(self: *App, previous: ?*Mounted, declaration: *Declaration, parent: *c.lv_obj_t, arena: Allocator) anyerror!*Plan {
        const old = if (previous) |node| (if (node.object != null) node else null) else null;
        const plan = try arena.create(Plan);
        plan.* = .{
            .mounted = old orelse try self.createMounted(declaration, parent),
            .declaration = declaration,
            .is_new = old == null,
        };
        errdefer self.discard(plan);
        // An externally deleted native subtree still has Zig records. They are
        // retired during commit, while new records are staged independently.
        const children = declaration.children.items;
        plan.children = try arena.alloc(*Plan, children.len);
        try plan.mounted.children.ensureTotalCapacity(self.allocator, children.len);
        if (declaration.kind == .grid) {
            const count = declaration.options.columns;
            const columns = try arena.alloc(i32, @as(usize, count) + 1);
            for (columns[0..count]) |*entry| entry.* = c.LV_GRID_FR(1);
            columns[count] = c.LV_GRID_TEMPLATE_LAST;
            const row_count = @max(1, (children.len + count - 1) / count);
            const rows = try arena.alloc(i32, row_count + 1);
            for (rows[0..row_count]) |*entry| entry.* = c.LV_GRID_CONTENT;
            rows[row_count] = c.LV_GRID_TEMPLATE_LAST;
            plan.columns = columns.ptr;
            plan.rows = rows.ptr;
        }
        for (children, 0..) |child, index| {
            var match: ?*Mounted = null;
            if (old) |node| {
                for (node.children.items, 0..) |candidate, old_index| {
                    if (core.sameIdentity(candidate.declaration, child, old_index, index)) {
                        match = candidate;
                        break;
                    }
                }
            }
            plan.children[index] = try self.prepare(match, child, plan.mounted.object.?, arena);
            plan.prepared += 1;
        }
        return plan;
    }

    fn discard(self: *App, plan: *Plan) void {
        for (plan.children[0..plan.prepared]) |child| self.discard(child);
        if (plan.is_new) self.destroyMounted(plan.mounted);
    }
    fn destroyMounted(self: *App, mounted: *Mounted) void {
        for (mounted.children.items) |child| self.destroyMounted(child);
        mounted.children.deinit(self.allocator);
        if (mounted.object) |object| {
            _ = c.lv_obj_remove_event_cb_with_user_data(object, eventCallback, mounted);
            c.lv_obj_delete(object);
        }
        self.allocator.destroy(mounted);
    }

    fn commit(self: *App, plan: *Plan) void {
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
        self.update(plan);
        mounted.declaration = plan.declaration;
        mounted.children.clearRetainingCapacity();
        for (plan.children, 0..) |child, index| {
            self.commit(child);
            mounted.children.appendAssumeCapacity(child.mounted);
            c.lv_obj_move_to_index(child.mounted.object.?, @intCast(index));
            if (plan.declaration.kind == .grid) {
                const columns = plan.declaration.options.columns;
                c.lv_obj_set_grid_cell(child.mounted.object.?, c.LV_GRID_ALIGN_STRETCH, @intCast(index % columns), 1, c.LV_GRID_ALIGN_START, @intCast(index / columns), 1);
            }
        }
        c.lv_obj_remove_flag(mounted.object.?, c.LV_OBJ_FLAG_HIDDEN);
    }

    fn update(_: *App, plan: *Plan) void {
        const mounted = plan.mounted;
        const object = mounted.object.?;
        const declaration = plan.declaration;
        const options = declaration.options;
        const container = switch (declaration.kind) {
            .root, .column, .row, .grid, .scroll => true,
            else => false,
        };
        if (container) {
            c.lv_obj_set_style_border_width(object, 0, 0);
            c.lv_obj_set_style_radius(object, 0, 0);
            c.lv_obj_set_style_pad_all(object, options.padding, 0);
            c.lv_obj_set_style_pad_row(object, options.gap, 0);
            c.lv_obj_set_style_pad_column(object, options.gap, 0);
            if (declaration.kind == .grid) {
                c.lv_obj_set_grid_dsc_array(object, plan.columns.?, plan.rows.?);
            } else {
                c.lv_obj_set_flex_flow(object, if (declaration.kind == .row) c.LV_FLEX_FLOW_ROW else c.LV_FLEX_FLOW_COLUMN);
            }
            if (declaration.kind != .scroll and declaration.kind != .root)
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
        }
        const width = options.width orelse (if (container or declaration.kind == .text_field) c.lv_pct(100) else c.LV_SIZE_CONTENT);
        const height = options.height orelse (switch (declaration.kind) {
            .root => c.lv_pct(100),
            .scroll => 200,
            else => c.LV_SIZE_CONTENT,
        });
        c.lv_obj_set_size(object, width, height);
        c.lv_obj_set_flex_grow(object, options.grow);
        c.lv_obj_set_state(object, c.LV_STATE_DISABLED, options.disabled);
        switch (declaration.kind) {
            .label => c.lv_label_set_text(object, declaration.text.ptr),
            .button => {
                c.lv_label_set_text(mounted.label.?, declaration.text.ptr);
                c.lv_obj_center(mounted.label.?);
            },
            .checkbox => {
                c.lv_checkbox_set_text(object, declaration.text.ptr);
                c.lv_obj_set_state(object, c.LV_STATE_CHECKED, declaration.checked);
            },
            .text_field => {
                // Preserve caret and selection when a redraw doesn't change text.
                const current = std.mem.span(c.lv_textarea_get_text(object));
                if (!std.mem.eql(u8, current, declaration.text))
                    c.lv_textarea_set_text(object, declaration.text.ptr);
            },
            else => {},
        }
    }

    fn eventCallback(event: ?*c.lv_event_t) callconv(.c) void {
        const e = event orelse return;
        const mounted: *Mounted = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
        const app = mounted.app;
        const code = c.lv_event_get_code(e);
        if (code == c.LV_EVENT_DELETE) {
            mounted.object = null;
            mounted.label = null;
            app.invalidate();
            return;
        }
        if (app.busy) return;
        const object = mounted.object orelse return;
        // Copy every callback/binding before invoking user code. Reconciliation
        // is deferred until dispatch unwinds, including nested native events.
        const declaration = mounted.declaration.*;
        app.dispatch_depth += 1;
        defer app.dispatch_depth -= 1;
        if (code == c.LV_EVENT_CLICKED and declaration.kind == .button) {
            if (declaration.options.on_click) |cb| cb.invoke(cb.context) catch |err| {
                app.event_error = err;
                app.invalidate();
            };
        } else if (code == c.LV_EVENT_VALUE_CHANGED) {
            if (declaration.bool_binding) |binding| {
                binding.set(c.lv_obj_has_state(object, c.LV_STATE_CHECKED)) catch |err| {
                    app.event_error = err;
                    app.invalidate();
                };
            }
            if (declaration.text_binding) |binding| {
                binding.set(std.mem.span(c.lv_textarea_get_text(object))) catch |err| {
                    app.event_error = err;
                    app.invalidate();
                };
            }
        }
    }
};

test {
    _ = @import("integration_tests.zig");
}
