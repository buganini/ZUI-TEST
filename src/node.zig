const std = @import("std");
const Allocator = std.mem.Allocator;
const state = @import("state.zig");
const Signal = state.Signal;
const Binding = state.Binding;

pub const Callback = struct {
    context: *anyopaque,
    invoke: *const fn (*anyopaque) anyerror!void,
};

pub fn callback(context: anytype, comptime function: anytype) Callback {
    const T = @TypeOf(context);
    return .{ .context = context, .invoke = struct {
        fn invoke(raw: *anyopaque) !void {
            try function(@as(T, @ptrCast(@alignCast(raw))));
        }
    }.invoke };
}

pub const Kind = enum { view, root, column, row, grid, scroll, splitter, label, button, checkbox, text_field };

pub const Options = struct {
    key: ?[]const u8 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    width_percent: ?u8 = null,
    height_percent: ?u8 = null,
    padding: i32 = 0,
    gap: i32 = 8,
    grow: u8 = 0,
    /// Hide without removing the retained node or its native control.
    visible: bool = true,
    disabled: bool = false,
    selected: bool = false,
    vertical: bool = false,
    text_color: ?u32 = null,
    background: ?u32 = null,
    small_text: bool = false,
    columns: u16 = 2,
    on_click: ?Callback = null,
};

pub const ViewOptions = struct { key: ?[]const u8 = null };

pub const Node = struct {
    kind: Kind,
    options: Options,
    text: [:0]const u8,
    content: ?@import("view.zig").Content = null,
    checked: bool = false,
    bool_binding: ?Binding(bool) = null,
    text_binding: ?Binding([]const u8) = null,
    split_binding: ?Binding(u8) = null,
    split_ratio: u8 = 50,
    children: std.ArrayListUnmanaged(*Node) = std.ArrayListUnmanaged(*Node).empty,
};

/// Each render owns its declarations, copied keys, copied text and dependencies.
/// Kept alive until the next successful commit; failed builds discard it whole.
pub const Snapshot = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    root: Node,
    dependencies: std.ArrayListUnmanaged(*Signal) = std.ArrayListUnmanaged(*Signal).empty,
    failure: ?anyerror = null,

    pub fn create(allocator: Allocator) !*Snapshot {
        const self = try allocator.create(Snapshot);
        self.* = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root = .{ .kind = .root, .options = .{}, .text = "" },
        };
        return self;
    }
    pub fn destroy(self: *Snapshot) void {
        const allocator = self.allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }
    pub fn builder(self: *Snapshot) Builder {
        return .{ .snapshot = self, .parent = &self.root };
    }
    fn fail(self: *Snapshot, err: anyerror) void {
        if (self.failure == null) self.failure = err;
    }
    /// Called once content() returns, before preparing subscriptions or widgets.
    /// A failed snapshot remains failed; the next render uses a fresh snapshot.
    pub fn finish(self: *Snapshot) !void {
        if (self.failure) |err| return err;
        validate(&self.root) catch |err| {
            self.fail(err);
            return err;
        };
    }
    fn validate(node: *const Node) error{InvalidPaneCount}!void {
        if (node.kind == .splitter and node.children.items.len != 2) return error.InvalidPaneCount;
        for (node.children.items) |child| try validate(child);
    }
};

/// A builder is a handle into one render's arena; never keep it after content().
pub const Builder = struct {
    snapshot: *Snapshot,
    // Failed containers return a valid handle with no parent. All handles share
    // the snapshot's first error, including copies made before the failure.
    parent: ?*Node,

    fn active(self: *const Builder) bool {
        return self.parent != null and self.snapshot.failure == null;
    }
    /// Report a custom declaration error without committing a partial tree.
    pub fn fail(self: *Builder, err: anyerror) void {
        self.snapshot.fail(err);
    }
    pub fn track(self: *Builder, signal: *Signal) void {
        if (!self.active()) return;
        if (std.mem.indexOfScalar(*Signal, self.snapshot.dependencies.items, signal) == null)
            self.snapshot.dependencies.append(self.snapshot.arena.allocator(), signal) catch |err| self.fail(err);
    }
    fn add(self: *Builder, kind: Kind, text: []const u8, options: Options) ?*Node {
        if (!self.active()) return null;
        return self.addFallible(kind, text, options) catch |err| {
            self.fail(err);
            return null;
        };
    }
    fn addFallible(self: *Builder, kind: Kind, text: []const u8, options: Options) !*Node {
        if (options.padding < 0 or options.gap < 0 or
            (options.width != null and options.width.? < 0) or
            (options.height != null and options.height.? < 0)) return error.InvalidLayout;
        if (kind == .grid and options.columns == 0) return error.InvalidLayout;
        if (options.width_percent) |percent| {
            if (percent > 100 or options.width != null) return error.InvalidLayout;
        }
        if (options.height_percent) |percent| {
            if (percent > 100 or options.height != null) return error.InvalidLayout;
        }
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        if (options.key) |key| {
            if (key.len == 0) return error.EmptyKey;
            for (self.parent.?.children.items) |child| {
                if (child.options.key) |other| {
                    if (std.mem.eql(u8, key, other)) return error.DuplicateKey;
                }
            }
        }
        const allocator = self.snapshot.arena.allocator();
        const node = try allocator.create(Node);
        const copied_text = try allocator.allocSentinel(u8, text.len, 0);
        @memcpy(copied_text, text);
        node.* = .{ .kind = kind, .options = options, .text = copied_text };
        if (options.key) |key| node.options.key = try allocator.dupe(u8, key);
        try self.parent.?.children.append(allocator, node);
        return node;
    }
    fn container(self: *Builder, kind: Kind, options: Options) Builder {
        return .{ .snapshot = self.snapshot, .parent = self.add(kind, "", options) };
    }
    /// A virtual subtree with its own subscriptions. No native wrapper is added.
    /// The borrowed model must remain at a stable address until removal.
    pub fn view(self: *Builder, model: anytype, options: ViewOptions) void {
        const node = self.add(.view, "", .{ .key = options.key }) orelse return;
        node.content = @import("view.zig").Content.init(model);
    }
    pub fn vbox(self: *Builder, options: Options) Builder {
        return self.container(.column, options);
    }
    pub fn hbox(self: *Builder, options: Options) Builder {
        return self.container(.row, options);
    }
    pub fn scroll(self: *Builder, options: Options) Builder {
        return self.container(.scroll, options);
    }
    pub fn grid(self: *Builder, options: Options) Builder {
        return self.container(.grid, options);
    }
    /// Exactly two child panes. Ratio is a percentage, clamped to 10..90.
    /// Drag the divider or focus it and use the arrow keys to resize.
    pub fn splitter(self: *Builder, ratio: Binding(u8), options: Options) Builder {
        if (!self.active()) return .{ .snapshot = self.snapshot, .parent = null };
        const value = ratio.get(self);
        const panes = self.container(.splitter, options);
        if (panes.parent) |node| {
            node.split_binding = ratio;
            node.split_ratio = std.math.clamp(value, 10, 90);
        }
        return panes;
    }
    pub fn label(self: *Builder, text: []const u8, options: Options) void {
        _ = self.add(.label, text, options);
    }
    pub fn labelFmt(self: *Builder, comptime fmt: []const u8, args: anytype, options: Options) void {
        if (!self.active()) return;
        const text = std.fmt.allocPrint(self.snapshot.arena.allocator(), fmt, args) catch |err| {
            self.fail(err);
            return;
        };
        self.label(text, options);
    }
    pub fn button(self: *Builder, text: []const u8, options: Options) void {
        _ = self.add(.button, text, options);
    }
    pub fn checkbox(self: *Builder, text: []const u8, binding: Binding(bool), options: Options) void {
        if (!self.active()) return;
        const value = binding.get(self);
        const node = self.add(.checkbox, text, options) orelse return;
        node.checked = value;
        node.bool_binding = binding;
    }
    pub fn textField(self: *Builder, binding: Binding([]const u8), options: Options) void {
        if (!self.active()) return;
        const text = binding.get(self);
        const node = self.add(.text_field, text, options) orelse return;
        node.text_binding = binding;
    }
};

pub fn sameIdentity(old: *const Node, next: *const Node, old_index: usize, next_index: usize) bool {
    if (old.kind != next.kind) return false;
    if (next.kind == .view) {
        const a = old.content.?;
        const b = next.content.?;
        if (a.context != b.context or !std.mem.eql(u8, a.type_name, b.type_name)) return false;
    }
    if (next.options.key) |key|
        return if (old.options.key) |other| std.mem.eql(u8, key, other) else false;
    return old.options.key == null and old_index == next_index;
}
