const std = @import("std");
const zui = @import("root.zig");
const c = zui.native;
const a = std.testing.allocator;

const Model = struct {
    count: zui.State(i32),
    alternate: zui.State(i32),
    checked: zui.State(bool),
    show: zui.State(bool),
    text: zui.TextState,
    reversed: bool = false,
    length: usize = 3,
    use_alternate: bool = false,
    fail: bool = false,
    mutate: bool = false,
    duplicate: bool = false,
    app: ?*zui.App = null,
    reentrant_rejected: bool = false,

    fn init(allocator: std.mem.Allocator) !Model {
        return .{
            .count = zui.State(i32).init(allocator, 1),
            .alternate = zui.State(i32).init(allocator, 7),
            .checked = zui.State(bool).init(allocator, true),
            .show = zui.State(bool).init(allocator, true),
            .text = try zui.TextState.init(allocator, "initial"),
        };
    }
    fn deinit(self: *Model) void {
        self.text.deinit();
        self.show.deinit();
        self.checked.deinit();
        self.alternate.deinit();
        self.count.deinit();
    }
    pub fn build(self: *Model, ui: *zui.Builder) !void {
        var box = try ui.vbox(.{ .key = "main", .padding = 12 });
        const value = if (self.use_alternate) try self.alternate.get(ui) else try self.count.get(ui);
        try box.labelFmt("Count: {d}", .{value}, .{ .key = "count" });
        if (self.mutate) try self.count.set(42);
        if (self.fail) return error.BuilderFailed;
        if (self.duplicate) try box.label("duplicate", .{ .key = "count" });
        try box.button("+", .{ .key = "increment", .on_click = zui.callback(self, increment) });
        try box.checkbox("Enabled", self.checked.binding(), .{ .key = "check" });
        try box.textField(self.text.binding(), .{ .key = "text" });
        if (try self.show.get(ui))
            try box.button("Remove me", .{ .key = "remove", .on_click = zui.callback(self, remove) });
        var list = try box.hbox(.{ .key = "items" });
        const keys = [_][]const u8{ "a", "b", "c" };
        for (0..self.length) |index| {
            const i = if (self.reversed) self.length - 1 - index else index;
            try list.label(keys[i], .{ .key = keys[i] });
        }
        var grid = try box.grid(.{ .key = "grid", .columns = 2 });
        try grid.label("first", .{});
        try grid.label("second", .{});
        var scroll = try box.scroll(.{ .key = "scroll", .height = 60 });
        try scroll.label("scroll content", .{});
    }
    fn increment(self: *Model) !void {
        try self.count.set(self.count.peek() + 1);
        if (self.app) |app| {
            app.flush() catch |err| {
                if (err != error.ReentrantFlush) return err;
                self.reentrant_rejected = true;
            };
        }
    }
    fn remove(self: *Model) !void {
        try self.show.set(false);
    }
};

fn click(object: *c.lv_obj_t) void {
    _ = c.lv_obj_send_event(object, c.LV_EVENT_CLICKED, null);
}

test "native events update State, batch renders and safely remove their own control" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.App.create(a, &model, .{});
    defer app.destroy();
    model.app = app;
    try app.flush();
    const label = app.find("count").?;
    click(app.find("increment").?);
    click(app.find("increment").?);
    try std.testing.expectEqual(3, model.count.peek());
    try std.testing.expectEqual(1, app.render_count);
    try std.testing.expect(model.reentrant_rejected);
    try app.flush();
    try std.testing.expectEqual(2, app.render_count);
    try std.testing.expectEqual(label, app.find("count").?);
    try std.testing.expectEqualStrings("Count: 3", std.mem.span(c.lv_label_get_text(label)));
    click(app.find("remove").?);
    try app.flush();
    try std.testing.expect(app.find("remove") == null);
}

test "checkbox and editable text bind both ways without resetting the caret" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.App.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    const checkbox = app.find("check").?;
    c.lv_obj_set_state(checkbox, c.LV_STATE_CHECKED, false);
    _ = c.lv_obj_send_event(checkbox, c.LV_EVENT_VALUE_CHANGED, null);
    try std.testing.expect(!model.checked.peek());
    const text = app.find("text").?;
    c.lv_textarea_set_text(text, "edited");
    try std.testing.expectEqualStrings("edited", model.text.peek());
    c.lv_textarea_set_cursor_pos(text, 2);
    try model.count.set(9);
    try app.flush();
    try std.testing.expectEqual(text, app.find("text").?);
    try std.testing.expectEqual(2, c.lv_textarea_get_cursor_pos(text));
    try model.text.set("from model");
    try model.checked.set(true);
    try app.flush();
    try std.testing.expectEqualStrings("from model", std.mem.span(c.lv_textarea_get_text(text)));
    try std.testing.expect(c.lv_obj_has_state(checkbox, c.LV_STATE_CHECKED));
}

test "keyed reorder and removal preserve native identities and physical order" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.App.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    const first = app.find("a").?;
    const last = app.find("c").?;
    model.reversed = true;
    app.invalidate();
    try app.flush();
    try std.testing.expectEqual(first, app.find("a").?);
    try std.testing.expectEqual(last, c.lv_obj_get_child(app.find("items").?, 0));
    model.length = 2;
    app.invalidate();
    try app.flush();
    try std.testing.expect(app.find("c") == null);
    try std.testing.expectEqual(first, c.lv_obj_get_child(app.find("items").?, 1));
    c.lv_obj_update_layout(app.find("grid").?);
    try std.testing.expect(c.lv_obj_get_x(c.lv_obj_get_child(app.find("grid").?, 1)) >
        c.lv_obj_get_x(c.lv_obj_get_child(app.find("grid").?, 0)));
}

test "builder errors preserve the old tree and subscriptions and allow retry" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.App.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    const old = app.find("count").?;
    model.fail = true;
    model.use_alternate = true;
    app.invalidate();
    try std.testing.expectError(error.BuilderFailed, app.flush());
    try std.testing.expectEqual(old, app.find("count").?);
    try std.testing.expectEqualStrings("Count: 1", std.mem.span(c.lv_label_get_text(old)));
    try std.testing.expectEqual(1, model.count.signal.observers.items.len);
    try std.testing.expectEqual(0, model.alternate.signal.observers.items.len);
    model.fail = false;
    model.use_alternate = false;
    model.mutate = true;
    try std.testing.expectError(error.MutationDuringBuild, app.flush());
    try std.testing.expectEqual(1, model.count.peek());
    model.mutate = false;
    model.duplicate = true;
    try std.testing.expectError(error.DuplicateKey, app.flush());
    model.duplicate = false;
    model.use_alternate = true;
    try app.flush();
    const renders = app.render_count;
    try model.count.set(12);
    try app.flush();
    try std.testing.expectEqual(renders, app.render_count);
    try model.alternate.set(15);
    try app.flush();
    try std.testing.expectEqualStrings("Count: 15", std.mem.span(c.lv_label_get_text(old)));
}

test "externally deleted containers and root are rebuilt and SDL quit is deferred" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.App.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    c.lv_obj_delete(app.find("items").?);
    try app.flush();
    try std.testing.expect(app.find("a") != null);
    c.lv_obj_delete(c.lv_obj_get_parent(app.find("main").?));
    try app.flush();
    try std.testing.expect(app.find("count") != null);
    c.zui_host_push_quit();
    try std.testing.expect(!(try app.pump()));
    // Native objects must remain alive until App.destroy detaches its callbacks.
    try std.testing.expect(c.lv_is_initialized());
    try std.testing.expect(c.lv_obj_is_valid(app.find("count").?));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var model = try Model.init(allocator);
    defer model.deinit();
    const app = try zui.App.create(allocator, &model, .{});
    defer app.destroy();
    model.length = 1;
    try app.flush();
    const old = app.find("count").?;
    model.length = 3;
    try model.count.set(2);
    app.flush() catch |err| {
        try std.testing.expectEqual(old, app.find("count").?);
        try std.testing.expectEqualStrings("Count: 1", std.mem.span(c.lv_label_get_text(old)));
        return err;
    };
}

test "every Zig allocation failure while mounting or reconciling cleans up" {
    try std.testing.checkAllAllocationFailures(a, allocationScenario, .{});
}
