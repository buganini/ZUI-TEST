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

pub const Node = struct {
    parent: ?*Node = null,
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

/// A declaration handle into one content snapshot. Copies refer to the same
/// node; never retain a handle after content(). Factories and modifiers take
/// handles by value so temporary results can be chained without try.
pub const Builder = struct {
    snapshot: *Snapshot,
    // Current node: a container's insertion point or a widget being configured.
    // Null is an inert handle returned after a declaration failure.
    parent: ?*Node,

    fn active(self: Builder) bool {
        return self.parent != null and self.snapshot.failure == null;
    }
    fn inert(self: Builder) Builder {
        return .{ .snapshot = self.snapshot, .parent = null };
    }
    fn reject(self: Builder, err: anyerror) Builder {
        self.fail(err);
        return self.inert();
    }
    /// Report a custom declaration error without committing a partial tree.
    pub fn fail(self: Builder, err: anyerror) void {
        self.snapshot.fail(err);
    }
    pub fn track(self: Builder, signal: *Signal) void {
        if (!self.active()) return;
        if (std.mem.indexOfScalar(*Signal, self.snapshot.dependencies.items, signal) == null)
            self.snapshot.dependencies.append(self.snapshot.arena.allocator(), signal) catch |err| self.fail(err);
    }
    fn add(self: Builder, kind: Kind, text: []const u8) Builder {
        if (!self.active()) return self.inert();
        const node = self.addFallible(kind, text) catch |err| return self.reject(err);
        return .{ .snapshot = self.snapshot, .parent = node };
    }
    fn addFallible(self: Builder, kind: Kind, text: []const u8) !*Node {
        switch (self.parent.?.kind) {
            .root, .column, .row, .grid, .scroll, .splitter => {},
            else => return error.InvalidParent,
        }
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        const allocator = self.snapshot.arena.allocator();
        const node = try allocator.create(Node);
        const copied_text = try allocator.allocSentinel(u8, text.len, 0);
        @memcpy(copied_text, text);
        node.* = .{ .parent = self.parent, .kind = kind, .options = .{}, .text = copied_text };
        try self.parent.?.children.append(allocator, node);
        return node;
    }

    /// Copy the key into the snapshot; identity remains unique among siblings.
    pub fn key(self: Builder, value: []const u8) Builder {
        if (!self.active()) return self.inert();
        if (value.len == 0) return self.reject(error.EmptyKey);
        const node = self.parent.?;
        const parent = node.parent orelse return self.reject(error.InvalidRootModifier);
        for (parent.children.items) |sibling| {
            if (sibling == node) continue;
            if (sibling.options.key) |other| {
                if (std.mem.eql(u8, value, other)) return self.reject(error.DuplicateKey);
            }
        }
        const copy = self.snapshot.arena.allocator().dupe(u8, value) catch |err| return self.reject(err);
        node.options.key = copy;
        return self;
    }
    fn option(self: Builder, comptime field: []const u8, value: anytype) Builder {
        if (!self.active()) return self.inert();
        const node = self.parent.?;
        if (node.kind == .root) return self.reject(error.InvalidRootModifier);
        if (node.kind == .view) return self.reject(error.InvalidViewModifier);
        if (comptime std.mem.eql(u8, field, "width") or std.mem.eql(u8, field, "height") or
            std.mem.eql(u8, field, "padding") or std.mem.eql(u8, field, "gap"))
        {
            if (value < 0) return self.reject(error.InvalidLayout);
        }
        if (comptime std.mem.eql(u8, field, "width_percent") or std.mem.eql(u8, field, "height_percent")) {
            if (value > 100) return self.reject(error.InvalidLayout);
        }
        if (comptime std.mem.eql(u8, field, "columns")) {
            if (node.kind != .grid) return self.reject(error.InvalidModifier);
            if (value == 0) return self.reject(error.InvalidLayout);
        }
        if (comptime std.mem.eql(u8, field, "vertical")) {
            if (node.kind != .splitter) return self.reject(error.InvalidModifier);
        }
        if (comptime std.mem.eql(u8, field, "on_click")) {
            if (node.kind != .button) return self.reject(error.InvalidModifier);
        }
        @field(node.options, field) = value;
        return self;
    }
    /// Pixel and percentage sizes replace each other on the same axis.
    pub fn width(self: Builder, value: i32) Builder {
        const next = self.option("width", value);
        if (next.active()) next.parent.?.options.width_percent = null;
        return next;
    }
    pub fn height(self: Builder, value: i32) Builder {
        const next = self.option("height", value);
        if (next.active()) next.parent.?.options.height_percent = null;
        return next;
    }
    pub fn widthPercent(self: Builder, value: u8) Builder {
        const next = self.option("width_percent", value);
        if (next.active()) next.parent.?.options.width = null;
        return next;
    }
    pub fn heightPercent(self: Builder, value: u8) Builder {
        const next = self.option("height_percent", value);
        if (next.active()) next.parent.?.options.height = null;
        return next;
    }
    pub fn padding(self: Builder, value: i32) Builder {
        return self.option("padding", value);
    }
    pub fn gap(self: Builder, value: i32) Builder {
        return self.option("gap", value);
    }
    pub fn grow(self: Builder, value: u8) Builder {
        return self.option("grow", value);
    }
    pub fn visible(self: Builder, value: bool) Builder {
        return self.option("visible", value);
    }
    pub fn disabled(self: Builder, value: bool) Builder {
        return self.option("disabled", value);
    }
    pub fn selected(self: Builder, value: bool) Builder {
        return self.option("selected", value);
    }
    pub fn vertical(self: Builder, value: bool) Builder {
        return self.option("vertical", value);
    }
    pub fn textColor(self: Builder, value: u32) Builder {
        return self.option("text_color", value);
    }
    pub fn background(self: Builder, value: u32) Builder {
        return self.option("background", value);
    }
    pub fn smallText(self: Builder, value: bool) Builder {
        return self.option("small_text", value);
    }
    pub fn columns(self: Builder, value: u16) Builder {
        return self.option("columns", value);
    }
    pub fn onClick(self: Builder, value: Callback) Builder {
        return self.option("on_click", value);
    }

    /// A virtual subtree with its own subscriptions. Only key() applies to a
    /// virtual View; configure layout and visibility on its physical container.
    /// The borrowed model must remain at a stable address until removal.
    pub fn view(self: Builder, model: anytype) Builder {
        const child = self.add(.view, "");
        if (child.parent) |node| node.content = @import("view.zig").Content.init(model);
        return child;
    }
    pub fn vbox(self: Builder) Builder {
        return self.add(.column, "");
    }
    pub fn hbox(self: Builder) Builder {
        return self.add(.row, "");
    }
    pub fn scroll(self: Builder) Builder {
        return self.add(.scroll, "");
    }
    pub fn grid(self: Builder) Builder {
        return self.add(.grid, "");
    }
    /// Exactly two child panes. Ratio is a percentage, clamped to 10..90.
    /// Drag the divider or focus it and use the arrow keys to resize.
    pub fn splitter(self: Builder, ratio: Binding(u8)) Builder {
        if (!self.active()) return self.inert();
        const value = ratio.get(self);
        const panes = self.add(.splitter, "");
        if (panes.parent) |node| {
            node.split_binding = ratio;
            node.split_ratio = std.math.clamp(value, 10, 90);
        }
        return panes;
    }
    pub fn label(self: Builder, text: []const u8) Builder {
        return self.add(.label, text);
    }
    pub fn labelFmt(self: Builder, comptime fmt: []const u8, args: anytype) Builder {
        if (!self.active()) return self.inert();
        const text = std.fmt.allocPrint(self.snapshot.arena.allocator(), fmt, args) catch |err| return self.reject(err);
        return self.label(text);
    }
    pub fn button(self: Builder, text: []const u8) Builder {
        return self.add(.button, text);
    }
    pub fn checkbox(self: Builder, text: []const u8, binding: Binding(bool)) Builder {
        if (!self.active()) return self.inert();
        const value = binding.get(self);
        const child = self.add(.checkbox, text);
        if (child.parent) |node| {
            node.checked = value;
            node.bool_binding = binding;
        }
        return child;
    }
    pub fn textField(self: Builder, binding: Binding([]const u8)) Builder {
        if (!self.active()) return self.inert();
        const text = binding.get(self);
        const child = self.add(.text_field, text);
        if (child.parent) |node| node.text_binding = binding;
        return child;
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
