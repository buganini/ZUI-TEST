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
    app: ?*zui.Application = null,
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
    pub fn content(self: *Model, ui: *zui.Builder) !void {
        const box = ui.vbox(.{}).id("main").layout(.{ .padding = 12 });
        const value = if (self.use_alternate) self.alternate.get(ui) else self.count.get(ui);
        _ = box.labelFmt("Count: {d}", .{value}).id("count");
        if (self.mutate) try self.count.set(42);
        if (self.fail) return error.BuilderFailed;
        if (self.duplicate) _ = box.label("duplicate").id("count");
        _ = box.button("+").id("increment").click(zui.callback(self, increment));
        _ = box.checkbox("Enabled", self.checked.binding()).id("check");
        _ = box.textField(self.text.binding()).id("text");
        if (self.show.get(ui))
            _ = box.button("Remove me").id("remove").click(zui.callback(self, remove));
        const list = box.hbox(.{}).id("items");
        const keys = [_][]const u8{ "a", "b", "c" };
        for (0..self.length) |index| {
            const i = if (self.reversed) self.length - 1 - index else index;
            _ = list.label(keys[i]).id(keys[i]);
        }
        const grid = box.grid(.{}).id("grid").columns(2);
        _ = grid.label("first");
        _ = grid.label("second");
        const scroll = box.scroll(.{}).id("scroll").layout(.{ .height = 60 });
        _ = scroll.label("scroll content");
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
    const app = try zui.Application.create(a, &model, .{});
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
    const app = try zui.Application.create(a, &model, .{});
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
    const app = try zui.Application.create(a, &model, .{});
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
    const app = try zui.Application.create(a, &model, .{});
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
    try std.testing.expectError(error.DuplicateId, app.flush());
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

test "void content runs to completion before deferred errors reject the tree and subscriptions" {
    const Deferred = struct {
        first: zui.State(i32),
        alternate: zui.State(i32),
        fail: bool = false,
        completed: bool = false,
        pub fn content(self: *@This(), ui: *zui.Builder) void {
            self.completed = false;
            const value = if (self.fail) self.alternate.get(ui) else self.first.get(ui);
            _ = ui.labelFmt("Value: {d}", .{value}).id("value");
            if (self.fail) {
                _ = ui.button("Duplicate").id("value");
                const invalid = ui.grid(.{}).columns(0);
                const nested = invalid.vbox(.{});
                _ = nested.label("Ignored");
                ui.fail(error.LaterError);
            }
            self.completed = true;
        }
    };
    var model = Deferred{
        .first = zui.State(i32).init(a, 1),
        .alternate = zui.State(i32).init(a, 9),
    };
    defer model.first.deinit();
    defer model.alternate.deinit();
    const app = try zui.Application.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    const original = app.find("value").?;
    model.fail = true;
    model.completed = false;
    app.invalidate();
    try std.testing.expectError(error.DuplicateId, app.flush());
    try std.testing.expect(model.completed);
    try std.testing.expectEqual(1, app.render_count);
    try std.testing.expectEqual(original, app.find("value").?);
    try std.testing.expectEqualStrings("Value: 1", std.mem.span(c.lv_label_get_text(original)));
    try std.testing.expectEqual(1, model.first.signal.observers.items.len);
    try std.testing.expectEqual(0, model.alternate.signal.observers.items.len);
    model.fail = false;
    try model.first.set(7);
    try app.flush();
    try std.testing.expectEqual(2, app.render_count);
    try std.testing.expectEqualStrings("Value: 7", std.mem.span(c.lv_label_get_text(original)));
}

test "fallible content shares the deferred boundary without replacing an earlier error" {
    const Fallible = struct {
        declaration_error: bool = false,
        pub fn content(self: *@This(), ui: *zui.Builder) !void {
            if (self.declaration_error) ui.fail(error.DeclarationFailed);
            return error.ModelFailed;
        }
    };
    var model = Fallible{};
    const app = try zui.Application.create(a, &model, .{});
    defer app.destroy();
    try std.testing.expectError(error.ModelFailed, app.flush());
    model.declaration_error = true;
    try std.testing.expectError(error.DeclarationFailed, app.flush());
    try std.testing.expectEqual(0, app.render_count);
}

test "externally deleted containers and root are rebuilt and SDL quit is deferred" {
    var model = try Model.init(a);
    defer model.deinit();
    const app = try zui.Application.create(a, &model, .{});
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
    // Native objects must remain alive until Application.destroy detaches its callbacks.
    try std.testing.expect(c.lv_is_initialized());
    try std.testing.expect(c.lv_obj_is_valid(app.find("count").?));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var model = try Model.init(allocator);
    defer model.deinit();
    const app = try zui.Application.create(allocator, &model, .{});
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

test "splitter resizes retained panes, clamps keyboard input and rejects missing panes" {
    const Split = struct {
        ratio: zui.State(u8),
        vertical: bool = false,
        missing: bool = false,
        pub fn content(self: *@This(), ui: *zui.Builder) !void {
            const panes = ui.splitter(.{ .vertical = self.vertical })
                .id("panes")
                .ratio(self.ratio.binding())
                .layout(.{ .height_percent = 100 });
            const left = panes.vbox(.{}).id("left");
            _ = left.label("Code");
            if (!self.missing) {
                const right = panes.vbox(.{}).id("right");
                _ = right.label("Result");
            }
        }
    };
    var model = Split{ .ratio = zui.State(u8).init(a, 50) };
    defer model.ratio.deinit();
    const app = try zui.Application.create(a, &model, .{ .width = 800, .height = 600 });
    defer app.destroy();
    try app.flush();
    const panes = app.find("panes").?;
    const left = app.find("left").?;
    const right = app.find("right").?;
    const handle = c.lv_obj_get_child(panes, 1);
    c.lv_obj_update_layout(panes);
    const initial = c.lv_obj_get_width(left);
    const Pointer = struct {
        point: c.lv_point_t,
        pressed: bool = true,
        fn read(indev: ?*c.lv_indev_t, data: [*c]c.lv_indev_data_t) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(c.lv_indev_get_user_data(indev).?));
            data.*.point = self.point;
            data.*.state = if (self.pressed) c.LV_INDEV_STATE_PRESSED else c.LV_INDEV_STATE_RELEASED;
        }
    };
    var coords: c.lv_area_t = undefined;
    c.lv_obj_get_coords(handle, &coords);
    var pointer_data = Pointer{ .point = .{ .x = coords.x1 + 4, .y = coords.y1 + 20 } };
    const pointer = c.lv_indev_create().?;
    defer c.lv_indev_delete(pointer);
    c.lv_indev_set_type(pointer, c.LV_INDEV_TYPE_POINTER);
    c.lv_indev_set_mode(pointer, c.LV_INDEV_MODE_EVENT);
    c.lv_indev_set_user_data(pointer, &pointer_data);
    c.lv_indev_set_read_cb(pointer, Pointer.read);
    c.lv_indev_read(pointer);
    pointer_data.point.x = 560;
    c.lv_indev_read(pointer);
    try app.flush();
    try std.testing.expectEqual(70, model.ratio.peek());
    c.lv_obj_update_layout(panes);
    try std.testing.expect(c.lv_obj_get_width(left) > initial);
    pointer_data.pressed = false;
    c.lv_indev_read(pointer);
    try model.ratio.set(50);
    try app.flush();
    var key: u32 = c.LV_KEY_RIGHT;
    for (0..3) |_| _ = c.lv_obj_send_event(handle, c.LV_EVENT_KEY, &key);
    try std.testing.expectEqual(65, model.ratio.peek());
    try app.flush();
    c.lv_obj_update_layout(panes);
    try std.testing.expect(c.lv_obj_get_width(left) > initial);
    try std.testing.expectEqual(right, app.find("right").?);
    try std.testing.expectEqual(handle, c.lv_obj_get_child(panes, 1));
    for (0..20) |_| _ = c.lv_obj_send_event(handle, c.LV_EVENT_KEY, &key);
    try std.testing.expectEqual(90, model.ratio.peek());
    model.vertical = true;
    try model.ratio.set(30);
    try app.flush();
    c.lv_obj_update_layout(panes);
    try std.testing.expect(c.lv_obj_get_y(right) > c.lv_obj_get_y(left));
    try std.testing.expect(c.lv_obj_get_height(left) < c.lv_obj_get_height(right));
    model.missing = true;
    app.invalidate();
    try std.testing.expectError(error.InvalidPaneCount, app.flush());
    try std.testing.expectEqual(right, app.find("right").?);
}

test "inverse boxes, spacers, dividers, clickable labels and unbound splitters" {
    const Layouts = struct {
        inverse: bool = false,
        clicks: usize = 0,
        pub fn content(self: *@This(), ui: *zui.Builder) void {
            const root = ui.vbox(.{}).layout(.{ .height_percent = 100 });
            const row = root.hbox(.{ .inverse = self.inverse }).id("row");
            _ = row.label("Left").id("left").click(zui.callback(self, clicked));
            _ = row.spacer().id("gap");
            _ = row.divider().id("line");
            _ = row.label("Right").id("right");
            const panes = root.splitter(.{}).id("panes").layout(.{ .height = 200 });
            _ = panes.label("A").id("a");
            _ = panes.label("B").id("b");
        }
        fn clicked(self: *@This()) !void {
            self.clicks += 1;
        }
    };
    var model = Layouts{};
    const app = try zui.Application.create(a, &model, .{ .width = 800, .height = 600 });
    defer app.destroy();
    try app.flush();
    const row = app.find("row").?;
    const left = app.find("left").?;
    const right = app.find("right").?;
    c.lv_obj_update_layout(row);
    // The spacer pushes the last label to the far edge; the divider spans the row.
    try std.testing.expect(c.lv_obj_get_width(app.find("gap").?) > 400);
    try std.testing.expectEqual(1, c.lv_obj_get_width(app.find("line").?));
    try std.testing.expect(c.lv_obj_get_x(right) > c.lv_obj_get_x(left));
    model.inverse = true;
    app.invalidate();
    try app.flush();
    c.lv_obj_update_layout(row);
    try std.testing.expectEqual(left, app.find("left").?);
    try std.testing.expect(c.lv_obj_get_x(right) < c.lv_obj_get_x(left));
    click(left);
    try std.testing.expectEqual(1, model.clicks);

    // Without .ratio(), keyboard resizing is kept by the retained splitter.
    const panes = app.find("panes").?;
    const handle = c.lv_obj_get_child(panes, 1);
    c.lv_obj_update_layout(panes);
    const initial = c.lv_obj_get_width(app.find("a").?);
    var key: u32 = c.LV_KEY_RIGHT;
    _ = c.lv_obj_send_event(handle, c.LV_EVENT_KEY, &key);
    try app.flush();
    model.inverse = false;
    app.invalidate();
    try app.flush();
    c.lv_obj_update_layout(panes);
    try std.testing.expect(c.lv_obj_get_width(app.find("a").?) > initial);
}
