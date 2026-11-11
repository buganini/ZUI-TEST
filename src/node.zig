const std = @import("std");
const Allocator = std.mem.Allocator;
const state = @import("state.zig");
const Signal = state.Signal;
const Binding = state.Binding;
const View = @import("view.zig").View;
const Content = @import("view.zig").Content;

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

/// Like CPPUI's Node: one declaration per render. A matched declaration takes
/// over its predecessor's native state in update(prev); the predecessor is then
/// retired. The flags drive dom.sync(), and per-kind behavior lives in the
/// backend selected at build time (see src/lvgl/backend.zig).
pub const Node = struct {
    allocator: Allocator,
    kind: Kind,
    /// The View whose content() declared this node (CPPUI's cppui_root).
    owner: ?*View = null,
    parent: ?*Node = null,
    dom_parent: ?*Node = null,
    children: List = .empty,

    is_terminal: bool = false,
    is_outoforder: bool = false,
    is_reversed_order: bool = false,
    is_view: bool = false,
    is_virtual: bool = false,
    is_movable: bool = true,
    is_grid_layout: bool = false,
    destroyed: bool = false,

    options: Options = .{},
    text: [:0]const u8 = "",
    checked: bool = false,
    bool_binding: ?Binding(bool) = null,
    text_binding: ?Binding([]const u8) = null,
    split_binding: ?Binding(u8) = null,
    split_ratio: u8 = 50,

    /// Retained native state, moved from the previous declaration on update.
    ui: Backend.Widget = .{},

    pub const List = std.ArrayListUnmanaged(*Node);
    /// The backend chosen at build time, like cppui/backend.hpp.
    pub const Backend = @import("backend");

    pub fn init(allocator: Allocator, kind: Kind) Node {
        var node = Node{ .allocator = allocator, .kind = kind };
        switch (kind) {
            .label, .button, .checkbox, .text_field => node.is_terminal = true,
            .spacer, .divider => {
                node.is_terminal = true;
                node.is_movable = false;
            },
            .grid => node.is_grid_layout = true,
            .view => {
                node.is_view = true;
                node.is_virtual = true;
            },
            .root, .column, .row, .scroll, .splitter => {},
        }
        return node;
    }

    /// CPPUI's operator==: same type, same grid identity, and the same id when
    /// either has one. Unkeyed siblings of one type match in sequence.
    pub fn eql(self: *const Node, other: *const Node) bool {
        if (self.kind != other.kind) return false;
        if (self.kind == .view) {
            // A View is its model here: a different model is a different View.
            const a = View.fromConst(self).content;
            const b = View.fromConst(other).content;
            if (a.context != b.context or !std.mem.eql(u8, a.type_name, b.type_name)) return false;
        }
        const cell = gridIdentity(self);
        const other_cell = gridIdentity(other);
        if ((cell == null) != (other_cell == null)) return false;
        if (cell) |value| if (!std.meta.eql(value, other_cell.?)) return false;
        if (self.options.id != null or other.options.id != null) {
            const a = self.options.id orelse return false;
            const b = other.options.id orelse return false;
            return std.mem.eql(u8, a, b);
        }
        return true;
    }
    fn gridIdentity(node: *const Node) ?GridCell {
        const cell = node.options.grid;
        return if (cell.row != null and cell.column != null) cell else null;
    }

    /// Native insertion point for children: this node's native, or the nearest
    /// physical ancestor's. Null means the backend's top level.
    pub fn inner(self: *Node) ?Backend.Native {
        if (Backend.native(self)) |native| return native;
        return if (self.parent) |parent| parent.inner() else null;
    }
    /// This node's native, or a virtual node's first physical descendant.
    pub fn outer(self: *Node) ?Backend.Native {
        if (Backend.native(self)) |native| return native;
        if (self.children.items.len > 0) return self.children.items[0].outer();
        return null;
    }

    pub fn update(self: *Node, prev: ?*Node) !void {
        if (self.is_view) return View.from(self).update();
        try Backend.update(self, prev);
    }
    pub fn postUpdate(self: *Node) void {
        if (!self.is_virtual) Backend.postUpdate(self);
    }
    pub fn postSync(self: *Node) !void {
        if (!self.is_virtual) try Backend.postSync(self);
    }
    pub fn addChild(self: *Node, index: usize, child: *Node) void {
        if (!self.is_virtual) Backend.addChild(self, index, child);
    }
    pub fn removeChild(self: *Node, index: usize, child: *Node) void {
        if (!self.is_virtual) Backend.removeChild(self, index, child);
    }
    /// Release native state. `direct` deletes the native object itself;
    /// otherwise a deleted native ancestor owns it.
    pub fn destroy(self: *Node, direct: bool) void {
        if (!self.is_virtual) Backend.destroy(self, direct);
    }
    /// Free the declaration after destroy() or after a successor adopted its
    /// native state. Children are owned by the caller.
    pub fn free(self: *Node) void {
        const allocator = self.allocator;
        Backend.release(self);
        self.children.deinit(allocator);
        if (self.text.len > 0) allocator.free(self.text);
        if (self.options.id) |value| allocator.free(value);
        if (self.options.placeholder) |value| allocator.free(value);
        if (self.is_view) {
            const view = View.from(self);
            view.observer.deinit();
            allocator.destroy(view);
        } else allocator.destroy(self);
    }

    /// CPPUI's findDomOffsetForNode without the offset cache: the number of
    /// native children before `target` under this physical node.
    pub fn findDomOffset(self: *Node, target: *Node, offset: *usize) bool {
        if (self == target) {
            offset.* = 0;
            return true;
        }
        var current: usize = 0;
        for (self.children.items) |child| {
            if (child == target) {
                offset.* = current;
                return true;
            }
            if (child.is_virtual) {
                var nested: usize = 0;
                const found = child.findDomOffset(target, &nested);
                current += nested;
                if (found) {
                    offset.* = current;
                    return true;
                }
            } else if (!child.is_outoforder) current += 1;
        }
        offset.* = current;
        return false;
    }
};

/// Per-render declaration context: the View being built, its first error and
/// the Signals read so far.
pub const Build = struct {
    allocator: Allocator,
    view: *View,
    failure: ?anyerror = null,
    dependencies: std.ArrayListUnmanaged(*Signal) = .empty,

    pub fn fail(self: *Build, err: anyerror) void {
        if (self.failure == null) self.failure = err;
    }
};

/// A declaration handle, like the scope objects CPPUI's constructors push.
/// Copies refer to the same node; never retain a handle after content().
/// Factories and modifiers take handles by value so temporary results can be
/// chained without try. After a failure every handle is inert.
pub const Builder = struct {
    build: *Build,
    // Current node: a container's insertion point or a widget being configured.
    // Null is an inert handle returned after a declaration failure.
    parent: ?*Node,

    fn active(self: Builder) bool {
        return self.parent != null and self.build.failure == null;
    }
    fn inert(self: Builder) Builder {
        return .{ .build = self.build, .parent = null };
    }
    fn reject(self: Builder, err: anyerror) Builder {
        self.fail(err);
        return self.inert();
    }
    /// Report a custom declaration error; the View keeps its mounted tree.
    pub fn fail(self: Builder, err: anyerror) void {
        self.build.fail(err);
    }
    pub fn track(self: Builder, signal: *Signal) void {
        if (!self.active()) return;
        const deps = &self.build.dependencies;
        if (std.mem.indexOfScalar(*Signal, deps.items, signal) == null)
            deps.append(self.build.allocator, signal) catch |err| self.fail(err);
    }
    fn isRoot(self: Builder, node: *const Node) bool {
        return node == &self.build.view.node;
    }
    fn add(self: Builder, kind: Kind, text: []const u8) Builder {
        if (!self.active()) return self.inert();
        const node = self.addFallible(kind, text) catch |err| return self.reject(err);
        return .{ .build = self.build, .parent = node };
    }
    fn copyText(self: Builder, text: []const u8) ![:0]const u8 {
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        if (text.len == 0) return "";
        const copy = try self.build.allocator.allocSentinel(u8, text.len, 0);
        @memcpy(copy, text);
        return copy;
    }
    fn addFallible(self: Builder, kind: Kind, text: []const u8) !*Node {
        const parent = self.parent.?;
        if (parent.is_terminal) return error.InvalidParent;
        const allocator = self.build.allocator;
        try parent.children.ensureUnusedCapacity(allocator, 1);
        const copied = try self.copyText(text);
        errdefer if (copied.len > 0) allocator.free(copied);
        const node = if (kind == .view) &(try allocator.create(View)).node else try allocator.create(Node);
        node.* = Node.init(allocator, kind);
        node.parent = parent;
        node.owner = self.build.view;
        node.text = copied;
        parent.children.appendAssumeCapacity(node);
        return node;
    }

    /// Copy the id; identity remains unique among siblings.
    pub fn id(self: Builder, value: []const u8) Builder {
        if (!self.active()) return self.inert();
        if (value.len == 0) return self.reject(error.EmptyId);
        const node = self.parent.?;
        if (self.isRoot(node)) return self.reject(error.InvalidRootModifier);
        for (node.parent.?.children.items) |sibling| {
            if (sibling == node) continue;
            if (sibling.options.id) |other| {
                if (std.mem.eql(u8, value, other)) return self.reject(error.DuplicateId);
            }
        }
        const copy = self.build.allocator.dupe(u8, value) catch |err| return self.reject(err);
        if (node.options.id) |old| self.build.allocator.free(old);
        node.options.id = copy;
        return self;
    }
    /// The node being configured, or null after a failure. Rejects the root
    /// and virtual Views, which have no native control to configure.
    fn physical(self: Builder) ?*Node {
        if (!self.active()) return null;
        const node = self.parent.?;
        if (self.isRoot(node)) {
            self.fail(error.InvalidRootModifier);
            return null;
        }
        if (node.is_view) {
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
    /// Declared coordinates join identity, as in PUI and CPPUI.
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
        const copy = self.copyText(text) catch |err| return self.reject(err);
        if (node.options.placeholder) |old| self.build.allocator.free(old);
        node.options.placeholder = if (copy.len > 0) copy else null;
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
        if (child.parent) |node| {
            const view = View.from(node);
            const declared = node.*;
            view.* = View.init(declared, Content.init(model));
            view.root = self.build.view.root;
        }
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
        const allocator = self.build.allocator;
        const text = std.fmt.allocPrint(allocator, fmt, args) catch |err| return self.reject(err);
        defer allocator.free(text);
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
