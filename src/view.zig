const std = @import("std");
const Allocator = std.mem.Allocator;
const node_module = @import("node.zig");
const Node = node_module.Node;
const Builder = node_module.Builder;
const Build = node_module.Build;
const state = @import("state.zig");
const dom = @import("dom.zig");

/// Borrowed model and content entry point. The model must remain at a stable
/// address until the View is removed.
pub const Content = struct {
    context: *anyopaque,
    type_name: []const u8,
    invoke: *const fn (*anyopaque, *Builder) void,

    pub fn init(model: anytype) Content {
        const T = @TypeOf(model);
        return .{ .context = model, .type_name = @typeName(T), .invoke = struct {
            fn content(raw: *anyopaque, ui: *Builder) void {
                const context: T = @ptrCast(@alignCast(raw));
                const result = context.content(ui);
                if (@TypeOf(result) != void) result catch |err| ui.fail(err);
            }
        }.content };
    }
};

/// Like CPPUI's View: a virtual node that declares its children with content()
/// and owns the subscriptions read while doing so. redraw() rebuilds only this
/// View and reconciles the result with dom.sync().
pub const View = struct {
    node: Node,
    content: Content,
    observer: state.Observer,
    root: ?*Root = null,
    render_count: usize = 0,

    pub fn init(node: Node, content: Content) View {
        return .{ .node = node, .content = content, .observer = state.Observer.init(node.allocator) };
    }
    pub fn from(node: *Node) *View {
        return @fieldParentPtr("node", node);
    }
    pub fn fromConst(node: *const Node) *const View {
        return @fieldParentPtr("node", node);
    }
    pub fn invalidate(self: *View) void {
        self.observer.dirty = true;
    }

    /// CPPUI's View::update(): declare children into node.children. A failed
    /// build deletes the new declarations and keeps the previous subscriptions.
    pub fn update(self: *View) !void {
        const allocator = self.node.allocator;
        const original = self.node.children.items.len;
        var build = Build{ .allocator = allocator, .view = self };
        defer build.dependencies.deinit(allocator);
        errdefer {
            for (self.node.children.items[original..]) |child| dom.recurDelete(child, true);
            self.node.children.shrinkRetainingCapacity(original);
        }
        {
            state.build_depth += 1;
            defer state.build_depth -= 1;
            var ui = Builder{ .build = &build, .parent = &self.node };
            self.content.invoke(self.content.context, &ui);
        }
        if (build.failure) |err| return err;
        // Validate declarations before changing native UI.
        for (self.node.children.items[original..]) |child| try validate(child);
        try self.observer.prepare(build.dependencies.items);
        self.observer.commit(build.dependencies.items);
        self.render_count += 1;
    }
    /// Checks that need the whole declaration, like CPPUI's prepare().
    pub fn validate(node: *Node) error{InvalidPaneCount}!void {
        if (node.kind == .splitter and node.children.items.len != 2) return error.InvalidPaneCount;
        for (node.children.items) |child| try validate(child);
    }

    /// CPPUI's View::redraw(): rebuild, then sync against the mounted children
    /// at this View's offset in its physical parent.
    pub fn redraw(self: *View) !void {
        const allocator = self.node.allocator;
        const physical = self.node.dom_parent.?;
        var offset: usize = 0;
        _ = physical.findDomOffset(&self.node, &offset);
        var last = self.node.children;
        self.node.children = .empty;
        self.update() catch |err| {
            self.node.children.deinit(allocator);
            self.node.children = last;
            return err;
        };
        defer last.deinit(allocator);
        _ = try dom.sync(&self.node, physical, offset, &last, &self.node.children, 0);
    }
};

/// The backend-independent part of an Application: a physical root node that
/// hosts the root View, plus the guards that keep native callbacks outside
/// reconciliation. Must not move after init().
pub const Root = struct {
    allocator: Allocator,
    container: *Node,
    view: *View,
    busy: bool = false,
    dispatch_depth: usize = 0,
    event_error: ?anyerror = null,
    render_count: usize = 0,

    pub fn init(self: *Root, allocator: Allocator, model: anytype) !void {
        const container = try allocator.create(Node);
        errdefer allocator.destroy(container);
        container.* = Node.init(allocator, .root);
        try container.children.ensureTotalCapacity(allocator, 1);
        errdefer container.children.deinit(allocator);
        const view = try allocator.create(View);
        view.* = View.init(Node.init(allocator, .view), Content.init(model));
        view.root = self;
        view.node.parent = container;
        view.node.dom_parent = container;
        container.owner = view;
        container.children.appendAssumeCapacity(&view.node);
        self.* = .{ .allocator = allocator, .container = container, .view = view };
    }
    pub fn deinit(self: *Root) void {
        std.debug.assert(!self.busy and self.dispatch_depth == 0);
        self.busy = true;
        dom.recurDelete(self.container, true);
    }
    pub fn invalidate(self: *Root) void {
        self.view.invalidate();
    }
    /// Record a callback or binding error for the next flush() and keep the
    /// owning View dirty so it restores the model's value.
    pub fn report(self: *Root, node: *Node, err: anyerror) void {
        self.event_error = err;
        if (node.owner) |owner| owner.invalidate();
    }
    /// The native widget was deleted outside ZUI; its View remounts it.
    pub fn nativeDeleted(node: *Node) void {
        if (node.owner) |owner| owner.invalidate();
    }

    /// Redraw dirty Views, outermost first. Each redraw stands alone, as in
    /// CPPUI: an error leaves earlier redraws committed and the failed View
    /// dirty with its previous children mounted.
    pub fn flush(self: *Root) !void {
        if (self.busy or self.dispatch_depth != 0) return error.ReentrantFlush;
        if (self.event_error) |err| {
            self.event_error = null;
            return err;
        }
        self.busy = true;
        defer self.busy = false;
        if (Node.Backend.native(self.container) == null) {
            try self.container.update(null);
            self.view.invalidate();
        }
        var rendered = false;
        while (findDirty(&self.view.node)) |view| {
            view.redraw() catch |err| {
                view.invalidate();
                return err;
            };
            rendered = true;
        }
        if (rendered) self.render_count += 1;
    }
    fn findDirty(node: *Node) ?*View {
        if (node.is_view and View.from(node).observer.dirty) return View.from(node);
        for (node.children.items) |child| if (findDirty(child)) |view| return view;
        return null;
    }

    /// A borrowed retained View, valid until it is removed.
    pub fn findView(self: *Root, name: []const u8) ?*View {
        const found = findNode(self.container, name, true) orelse return null;
        return View.from(found);
    }
    /// The first depth-first native with this id, borrowed until removal.
    pub fn find(self: *Root, name: []const u8) ?Node.Backend.Native {
        const found = findNode(self.container, name, false) orelse return null;
        return Node.Backend.native(found);
    }
    pub fn findNode(node: *Node, name: []const u8, views: bool) ?*Node {
        if (node.options.id) |own| {
            if (std.mem.eql(u8, own, name) and node.is_view == views and
                (views or Node.Backend.native(node) != null)) return node;
        }
        for (node.children.items) |child| if (findNode(child, name, views)) |found| return found;
        return null;
    }
};
