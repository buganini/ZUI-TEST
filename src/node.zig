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

pub const Kind = enum { view, root, column, row, grid, scroll, splitter, spacer, divider, label, button, checkbox, text_field };

/// Default spacing between container children, matching PUI and CPPUI.
pub const default_gap: i32 = 10;

/// `.layout()` arguments, mirroring PUI's `layout(width, height, weight, padding)`.
/// Omitted fields keep their previous value. Percentages are a ZUI extension;
/// a pixel size and a percentage replace each other on the same axis.
pub const Layout = struct {
    width: ?i32 = null,
    height: ?i32 = null,
    weight: ?u8 = null,
    padding: ?i32 = null,
    width_percent: ?u8 = null,
    height_percent: ?u8 = null,
};

/// `.style()` arguments, mirroring PUI's `style(color, bgColor, fontSize)`.
/// Omitted fields keep their previous value. Containers pass text styles on.
pub const Style = struct {
    color: ?u32 = null,
    bg_color: ?u32 = null,
    font_size: ?u8 = null,
};

/// `HBox(inverse, gap)` / `VBox(inverse, gap)`.
pub const BoxOptions = struct {
    inverse: bool = false,
    gap: i32 = default_gap,
};
/// `Grid(gap)`.
pub const GridOptions = struct {
    gap: i32 = default_gap,
};
/// `.gridCell()` arguments, mirroring PUI's `grid(row, column, rowspan,
/// columnspan)`. Omitted fields keep their previous value. A manual Grid
/// places children that have both a row and a column.
pub const GridCell = struct {
    row: ?u16 = null,
    column: ?u16 = null,
    rowspan: ?u16 = null,
    columnspan: ?u16 = null,
};
/// `.columns(n, dense, expandChildren)` for automatic Grid placement.
pub const ColumnsOptions = struct {
    dense: ?bool = null,
    expand_children: bool = true,
};
/// `Scroll(vertical, horizontal)`: null lets content decide, like PUI.
pub const ScrollOptions = struct {
    vertical: ?bool = null,
    horizontal: ?bool = false,
};
/// `Splitter(vertical)`.
pub const SplitterOptions = struct {
    vertical: bool = false,
};

pub const Options = struct {
    id: ?[]const u8 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    width_percent: ?u8 = null,
    height_percent: ?u8 = null,
    padding: i32 = 0,
    gap: i32 = default_gap,
    weight: u8 = 0,
    inverse: bool = false,
    /// Hide without removing the retained node or its native control.
    visible: bool = true,
    disabled: bool = false,
    vertical: bool = false,
    scroll_vertical: ?bool = null,
    scroll_horizontal: ?bool = false,
    color: ?u32 = null,
    bg_color: ?u32 = null,
    font_size: ?u8 = null,
    grid: GridCell = .{},
    /// Null keeps manual Grid placement.
    columns: ?u16 = null,
    dense: ?bool = null,
    expand_children: bool = true,
    placeholder: ?[:0]const u8 = null,
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

/// Each render owns its declarations, copied ids, copied text and dependencies.
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
    fn copyText(self: Builder, text: []const u8) ![:0]const u8 {
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        const copy = try self.snapshot.arena.allocator().allocSentinel(u8, text.len, 0);
        @memcpy(copy, text);
        return copy;
    }
    fn addFallible(self: Builder, kind: Kind, text: []const u8) !*Node {
        switch (self.parent.?.kind) {
            .root, .column, .row, .grid, .scroll, .splitter => {},
            else => return error.InvalidParent,
        }
        const copied_text = try self.copyText(text);
        const allocator = self.snapshot.arena.allocator();
        const node = try allocator.create(Node);
        node.* = .{ .parent = self.parent, .kind = kind, .options = .{}, .text = copied_text };
        try self.parent.?.children.append(allocator, node);
        return node;
    }

    /// Copy the id into the snapshot; identity remains unique among siblings.
    pub fn id(self: Builder, value: []const u8) Builder {
        if (!self.active()) return self.inert();
        if (value.len == 0) return self.reject(error.EmptyId);
        const node = self.parent.?;
        const parent = node.parent orelse return self.reject(error.InvalidRootModifier);
        for (parent.children.items) |sibling| {
            if (sibling == node) continue;
            if (sibling.options.id) |other| {
                if (std.mem.eql(u8, value, other)) return self.reject(error.DuplicateId);
            }
        }
        const copy = self.snapshot.arena.allocator().dupe(u8, value) catch |err| return self.reject(err);
        node.options.id = copy;
        return self;
    }
    /// The node being configured, or null after a failure. Rejects the root
    /// and virtual Views, which have no native control to configure.
    fn physical(self: Builder) ?*Node {
        if (!self.active()) return null;
        const node = self.parent.?;
        if (node.kind == .root) {
            self.fail(error.InvalidRootModifier);
            return null;
        }
        if (node.kind == .view) {
            self.fail(error.InvalidViewModifier);
            return null;
        }
        return node;
    }
    /// Set only the given fields. A pixel size clears that axis's percentage
    /// and vice versa; if both are given, the percentage wins.
    pub fn layout(self: Builder, value: Layout) Builder {
        const node = self.physical() orelse return self.inert();
        inline for (.{ value.width, value.height, value.padding }) |field| {
            if (field) |pixels| if (pixels < 0) return self.reject(error.InvalidLayout);
        }
        inline for (.{ value.width_percent, value.height_percent }) |field| {
            if (field) |percent| if (percent > 100) return self.reject(error.InvalidLayout);
        }
        const options = &node.options;
        if (value.width) |pixels| {
            options.width = pixels;
            options.width_percent = null;
        }
        if (value.height) |pixels| {
            options.height = pixels;
            options.height_percent = null;
        }
        if (value.width_percent) |percent| {
            options.width_percent = percent;
            options.width = null;
        }
        if (value.height_percent) |percent| {
            options.height_percent = percent;
            options.height = null;
        }
        if (value.weight) |weight| options.weight = weight;
        if (value.padding) |padding| options.padding = padding;
        return self;
    }
    /// Set only the given fields; color and font size are inherited by children.
    pub fn style(self: Builder, value: Style) Builder {
        const node = self.physical() orelse return self.inert();
        if (value.font_size) |size| if (size == 0) return self.reject(error.InvalidStyle);
        if (value.color) |color| node.options.color = color;
        if (value.bg_color) |color| node.options.bg_color = color;
        if (value.font_size) |size| node.options.font_size = size;
        return self;
    }
    pub fn visible(self: Builder, value: bool) Builder {
        const node = self.physical() orelse return self.inert();
        node.options.visible = value;
        return self;
    }
    pub fn disabled(self: Builder, value: bool) Builder {
        const node = self.physical() orelse return self.inert();
        node.options.disabled = value;
        return self;
    }
    /// Automatic Grid placement over `value` equal columns.
    pub fn columns(self: Builder, value: u16, options: ColumnsOptions) Builder {
        const node = self.physical() orelse return self.inert();
        if (node.kind != .grid) return self.reject(error.InvalidModifier);
        if (value == 0) return self.reject(error.InvalidLayout);
        node.options.columns = value;
        node.options.dense = options.dense;
        node.options.expand_children = options.expand_children;
        return self;
    }
    /// A Grid child's cell, like PUI's `.grid()`. Automatic Grids use only spans.
    /// Declared coordinates join identity, as in PUI.
    pub fn gridCell(self: Builder, cell: GridCell) Builder {
        const node = self.physical() orelse return self.inert();
        if (cell.rowspan == 0 or cell.columnspan == 0) return self.reject(error.InvalidLayout);
        const target = &node.options.grid;
        inline for (@typeInfo(GridCell).@"struct".field_names) |name| {
            if (@field(cell, name)) |value| @field(target, name) = value;
        }
        return self;
    }
    /// Bind a splitter's first-pane percentage, clamped to 10..90. Without a
    /// binding, the splitter keeps its own ratio, as in PUI and CPPUI.
    pub fn ratio(self: Builder, binding: Binding(u8)) Builder {
        const node = self.physical() orelse return self.inert();
        if (node.kind != .splitter) return self.reject(error.InvalidModifier);
        node.split_binding = binding;
        node.split_ratio = std.math.clamp(binding.get(self), 10, 90);
        return self;
    }
    pub fn placeholder(self: Builder, text: []const u8) Builder {
        const node = self.physical() orelse return self.inert();
        if (node.kind != .text_field) return self.reject(error.InvalidModifier);
        node.options.placeholder = self.copyText(text) catch |err| return self.reject(err);
        return self;
    }
    /// Buttons and labels accept click callbacks.
    pub fn click(self: Builder, value: Callback) Builder {
        const node = self.physical() orelse return self.inert();
        if (node.kind != .button and node.kind != .label) return self.reject(error.InvalidModifier);
        node.options.on_click = value;
        return self;
    }

    /// A virtual subtree with its own subscriptions, like CPPUI's SubView.
    /// Only id() applies; configure layout and visibility on its physical
    /// container. The borrowed model must remain at a stable address until removal.
    pub fn subView(self: Builder, model: anytype) Builder {
        const child = self.add(.view, "");
        if (child.parent) |node| node.content = @import("view.zig").Content.init(model);
        return child;
    }
    fn box(self: Builder, kind: Kind, options: BoxOptions) Builder {
        if (options.gap < 0) return self.reject(error.InvalidLayout);
        const child = self.add(kind, "");
        if (child.parent) |node| {
            node.options.inverse = options.inverse;
            node.options.gap = options.gap;
        }
        return child;
    }
    pub fn vbox(self: Builder, options: BoxOptions) Builder {
        return self.box(.column, options);
    }
    pub fn hbox(self: Builder, options: BoxOptions) Builder {
        return self.box(.row, options);
    }
    pub fn scroll(self: Builder, options: ScrollOptions) Builder {
        const child = self.add(.scroll, "");
        if (child.parent) |node| {
            node.options.scroll_vertical = options.vertical;
            node.options.scroll_horizontal = options.horizontal;
        }
        return child;
    }
    pub fn grid(self: Builder, options: GridOptions) Builder {
        if (options.gap < 0) return self.reject(error.InvalidLayout);
        const child = self.add(.grid, "");
        if (child.parent) |node| node.options.gap = options.gap;
        return child;
    }
    /// Exactly two child panes. Drag the divider or focus it and use the arrow
    /// keys to resize; use .ratio() to bind the split percentage.
    pub fn splitter(self: Builder, options: SplitterOptions) Builder {
        const child = self.add(.splitter, "");
        if (child.parent) |node| node.options.vertical = options.vertical;
        return child;
    }
    /// Takes the remaining space along its HBox/VBox axis.
    pub fn spacer(self: Builder) Builder {
        return self.add(.spacer, "");
    }
    /// A thin separator line across its HBox/VBox axis.
    pub fn divider(self: Builder) Builder {
        return self.add(.divider, "");
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
    if (!std.meta.eql(gridIdentity(old), gridIdentity(next))) return false;
    if (next.options.id) |name|
        return if (old.options.id) |other| std.mem.eql(u8, name, other) else false;
    return old.options.id == null and old_index == next_index;
}
fn gridIdentity(declaration: *const Node) ?GridCell {
    const cell = declaration.options.grid;
    return if (cell.row != null and cell.column != null) cell else null;
}
