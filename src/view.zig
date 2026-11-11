const std = @import("std");
const node = @import("node.zig");
const state = @import("state.zig");

/// Borrowed model and content entry point. The model must remain at a stable
/// address until the View is removed.
pub const Content = struct {
    context: *anyopaque,
    invoke: *const fn (*anyopaque, *node.Builder) void,

    pub fn init(model: anytype) Content {
        const T = @TypeOf(model);
        return .{ .context = model, .invoke = struct {
            fn content(raw: *anyopaque, ui: *node.Builder) void {
                const context: T = @ptrCast(@alignCast(raw));
                const result = context.content(ui);
                if (@TypeOf(result) != void) result catch |err| ui.fail(err);
            }
        }.content };
    }
};

/// Retains one content snapshot and its reactive subscriptions. DOM mounting is
/// separate; prepare/commit lets it reject a failed update without losing state.
pub const View = struct {
    allocator: std.mem.Allocator,
    content: Content,
    observer: state.Observer,
    snapshot: ?*node.Snapshot = null,
    render_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, content: Content) View {
        return .{ .allocator = allocator, .content = content, .observer = state.Observer.init(allocator) };
    }
    pub fn deinit(self: *View) void {
        self.observer.deinit();
        if (self.snapshot) |snapshot| snapshot.destroy();
    }
    pub fn invalidate(self: *View) void {
        self.observer.dirty = true;
    }
    pub fn prepare(self: *View) !*node.Snapshot {
        const next = try node.Snapshot.create(self.allocator);
        errdefer next.destroy();
        {
            state.build_depth += 1;
            defer state.build_depth -= 1;
            var ui = next.builder();
            self.content.invoke(self.content.context, &ui);
        }
        try next.finish();
        try self.observer.prepare(next.dependencies.items);
        return next;
    }
    pub fn commit(self: *View, next: *node.Snapshot) void {
        self.observer.commit(next.dependencies.items);
        const previous = self.snapshot;
        self.snapshot = next;
        if (previous) |old| old.destroy();
        self.render_count += 1;
    }
};
