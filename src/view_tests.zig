const std = @import("std");
const zui = @import("root.zig");
const c = zui.native;
const a = std.testing.allocator;

const Child = struct {
    value: *zui.State(i32),
    key: []const u8,
    alternate: ?*zui.State(i32) = null,
    use_alternate: bool = false,
    fail: bool = false,
    calls: usize = 0,
    count: usize = 1,

    pub fn content(self: *@This(), ui: *zui.Builder) void {
        self.calls += 1;
        const value = if (self.use_alternate) self.alternate.?.get(ui) else self.value.get(ui);
        if (self.count > 0) _ = ui.labelFmt("{d}", .{value}).id(self.key);
        for (1..@max(1, self.count)) |_| _ = ui.label("extra");
        if (self.fail) ui.fail(error.ChildFailed);
    }
};
const Parent = struct {
    first: *Child,
    second: *Child,
    reverse: bool = false,
    show: bool = true,
    calls: usize = 0,
    pub fn content(self: *@This(), ui: *zui.Builder) void {
        self.calls += 1;
        const grid = ui.grid(.{}).id("grid").columns(2, .{});
        _ = grid.label("before").id("before");
        if (self.reverse) _ = grid.subView(self.second).id("second");
        if (self.show) _ = grid.subView(self.first).id("first");
        if (!self.reverse) _ = grid.subView(self.second).id("second");
        _ = grid.label("after").id("after");
    }
};
fn label(app: *zui.Application, key: []const u8) []const u8 {
    return std.mem.span(c.lv_label_get_text(app.find(key).?));
}

test "subviews update independently and keyed moves retain native and View identity" {
    var x = zui.State(i32).init(a, 1);
    defer x.deinit();
    var y = zui.State(i32).init(a, 2);
    defer y.deinit();
    var first = Child{ .value = &x, .key = "x" };
    var second = Child{ .value = &y, .key = "y" };
    var parent = Parent{ .first = &first, .second = &second };
    const app = try zui.Application.create(a, &parent, .{});
    defer app.destroy();
    try app.flush();
    const view = app.findView("first").?;
    const native = app.find("x").?;
    const grid = app.find("grid").?;
    try std.testing.expectEqual(4, c.lv_obj_get_child_count(grid));
    try std.testing.expectEqual(grid, c.lv_obj_get_parent(native));
    try x.set(3);
    try app.flush();
    try std.testing.expectEqual(1, parent.calls);
    try std.testing.expectEqual(1, second.calls);
    try std.testing.expectEqual(2, view.render_count);
    try std.testing.expectEqualStrings("3", label(app, "x"));
    parent.reverse = true;
    app.invalidate();
    try app.flush();
    try std.testing.expectEqual(view, app.findView("first").?);
    try std.testing.expectEqual(native, app.find("x").?);
    try std.testing.expectEqual(app.find("y").?, c.lv_obj_get_child(grid, 1));
    try std.testing.expectEqual(native, c.lv_obj_get_child(grid, 2));
    try std.testing.expectEqual(2, first.calls);
    parent.show = false;
    app.invalidate();
    try app.flush();
    try std.testing.expectEqual(0, x.signal.observers.items.len);
    try std.testing.expect(app.findView("first") == null);
    try std.testing.expect(app.find("x") == null);
    parent.show = true;
    app.invalidate();
    try app.flush();
    try std.testing.expectEqual(1, app.findView("first").?.render_count);
    try std.testing.expectEqualStrings("3", label(app, "x"));
}

test "failed sibling content rolls back the whole flush and dependency changes" {
    var x = zui.State(i32).init(a, 1);
    defer x.deinit();
    var y = zui.State(i32).init(a, 2);
    defer y.deinit();
    var first = Child{ .value = &x, .alternate = &y, .key = "x" };
    var second = Child{ .value = &x, .key = "y" };
    var parent = Parent{ .first = &first, .second = &second };
    const app = try zui.Application.create(a, &parent, .{});
    defer app.destroy();
    try app.flush();
    try std.testing.expectEqual(2, x.signal.observers.items.len);
    first.use_alternate = true;
    second.fail = true;
    try x.set(3);
    try std.testing.expectError(error.ChildFailed, app.flush());
    try std.testing.expectEqualStrings("1", label(app, "x"));
    try std.testing.expectEqualStrings("1", label(app, "y"));
    try std.testing.expectEqual(2, x.signal.observers.items.len);
    try std.testing.expectEqual(0, y.signal.observers.items.len);
    try std.testing.expectEqual(1, app.findView("first").?.render_count);
    second.fail = false;
    try app.flush();
    try std.testing.expectEqual(1, x.signal.observers.items.len);
    try std.testing.expectEqual(1, y.signal.observers.items.len);
    try std.testing.expectEqualStrings("2", label(app, "x"));
    try std.testing.expectEqualStrings("3", label(app, "y"));
    const first_calls = first.calls;
    try x.set(4);
    try app.flush();
    try std.testing.expectEqual(first_calls, first.calls);
}

test "virtual children flatten empty and multiple roots and reflow a clean parent grid" {
    var value = zui.State(i32).init(a, 1);
    defer value.deinit();
    var first = Child{ .value = &value, .key = "x", .count = 0 };
    var second = Child{ .value = &value, .key = "y", .count = 3 };
    var parent = Parent{ .first = &first, .second = &second };
    const app = try zui.Application.create(a, &parent, .{});
    defer app.destroy();
    try app.flush();
    const grid = app.find("grid").?;
    try std.testing.expectEqual(5, c.lv_obj_get_child_count(grid));
    first.count = 2;
    app.findView("first").?.invalidate();
    try app.flush();
    try std.testing.expectEqual(1, parent.calls);
    try std.testing.expectEqual(7, c.lv_obj_get_child_count(grid));
    try std.testing.expectEqual(app.find("x").?, c.lv_obj_get_child(grid, 1));
    try std.testing.expectEqual(app.find("y").?, c.lv_obj_get_child(grid, 3));
    try std.testing.expectEqual(app.find("after").?, c.lv_obj_get_child(grid, 6));
    c.lv_obj_update_layout(grid);
    try std.testing.expect(c.lv_obj_get_y(app.find("after").?) > c.lv_obj_get_y(app.find("y").?));
    first.count = 0;
    app.findView("first").?.invalidate();
    try app.flush();
    try std.testing.expectEqual(5, c.lv_obj_get_child_count(grid));
    try std.testing.expectEqual(app.find("y").?, c.lv_obj_get_child(grid, 1));
}

test "changing a keyed View model replaces subscriptions and native deletion dirties its owner" {
    var x = zui.State(i32).init(a, 1);
    defer x.deinit();
    var y = zui.State(i32).init(a, 2);
    defer y.deinit();
    var first = Child{ .value = &x, .key = "x" };
    var replacement = Child{ .value = &y, .key = "replacement" };
    var second = Child{ .value = &y, .key = "y" };
    var parent = Parent{ .first = &first, .second = &second };
    const app = try zui.Application.create(a, &parent, .{});
    defer app.destroy();
    try app.flush();
    c.lv_obj_delete(app.find("x").?);
    try app.flush();
    try std.testing.expectEqual(1, parent.calls);
    try std.testing.expectEqual(2, first.calls);
    try std.testing.expectEqual(1, second.calls);
    try std.testing.expect(app.find("x") != null);
    parent.first = &replacement;
    app.invalidate();
    try app.flush();
    try std.testing.expectEqual(0, x.signal.observers.items.len);
    try std.testing.expectEqual(2, y.signal.observers.items.len);
    try std.testing.expect(app.find("x") == null);
    try std.testing.expectEqualStrings("2", label(app, "replacement"));
    // Losing the physical parent also retires all affected View subscriptions.
    c.lv_obj_delete(app.find("grid").?);
    try app.flush();
    try std.testing.expectEqual(2, y.signal.observers.items.len);
    try std.testing.expect(app.find("replacement") != null);
}

test "visibility retains controls, caret and subscriptions while if removes them" {
    const Model = struct {
        visible: zui.State(bool),
        text: zui.TextState,
        present: bool = true,
        pub fn content(self: *@This(), ui: *zui.Builder) void {
            if (self.present) {
                const box = ui.vbox(.{}).id("box").visible(self.visible.get(ui));
                _ = box.textField(self.text.binding()).id("editor");
            }
            _ = ui.label("after").id("after");
        }
    };
    var model = Model{ .visible = zui.State(bool).init(a, true), .text = try zui.TextState.init(a, "hello") };
    defer model.visible.deinit();
    defer model.text.deinit();
    const app = try zui.Application.create(a, &model, .{});
    defer app.destroy();
    try app.flush();
    const box = app.find("box").?;
    const editor = app.find("editor").?;
    c.lv_textarea_set_cursor_pos(editor, 2);
    c.lv_obj_update_layout(box);
    const shown_y = c.lv_obj_get_y(app.find("after").?);
    try model.visible.set(false);
    try app.flush();
    c.lv_obj_update_layout(box);
    try std.testing.expect(c.lv_obj_has_flag(box, c.LV_OBJ_FLAG_HIDDEN));
    try std.testing.expect(!c.lv_obj_is_visible(editor));
    try std.testing.expect(c.lv_obj_get_y(app.find("after").?) < shown_y);
    try model.visible.set(true);
    try app.flush();
    try std.testing.expectEqual(box, app.find("box").?);
    try std.testing.expectEqual(editor, app.find("editor").?);
    try std.testing.expectEqual(2, c.lv_textarea_get_cursor_pos(editor));
    try std.testing.expect(c.lv_obj_is_visible(editor));
    model.present = false;
    app.invalidate();
    try app.flush();
    try std.testing.expect(app.find("editor") == null);
    try std.testing.expectEqual(0, model.text.signal.observers.items.len);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var value = zui.State(i32).init(allocator, 1);
    defer value.deinit();
    var first = Child{ .value = &value, .key = "x" };
    var second = Child{ .value = &value, .key = "y" };
    var parent = Parent{ .first = &first, .second = &second };
    const app = try zui.Application.create(allocator, &parent, .{});
    defer app.destroy();
    try app.flush();
    first.count = 3;
    second.count = 2;
    try value.set(2);
    app.flush() catch |err| {
        try std.testing.expectEqualStrings("1", label(app, "x"));
        try std.testing.expectEqualStrings("1", label(app, "y"));
        try std.testing.expectEqual(2, value.signal.observers.items.len);
        try std.testing.expectEqual(1, app.findView("first").?.render_count);
        return err;
    };
}

test "all subview and shared-subscription allocation failures preserve the committed tree" {
    try std.testing.checkAllAllocationFailures(a, allocationScenario, .{});
}

test "nested Views sharing a Signal commit all subscriptions before independent redraws" {
    const Branch = struct {
        value: *zui.State(i32),
        children: [12]Child,
        pub fn content(self: *@This(), ui: *zui.Builder) void {
            _ = ui.labelFmt("root {d}", .{self.value.get(ui)});
            for (&self.children) |*child| _ = ui.subView(child);
        }
    };
    const Root = struct {
        branch: *Branch,
        pub fn content(self: *@This(), ui: *zui.Builder) void {
            _ = ui.subView(self.branch).id("branch");
        }
    };
    var value = zui.State(i32).init(a, 1);
    defer value.deinit();
    var branch = Branch{ .value = &value, .children = undefined };
    for (&branch.children) |*child| child.* = .{ .value = &value, .key = "value" };
    var root = Root{ .branch = &branch };
    const app = try zui.Application.create(a, &root, .{});
    defer app.destroy();
    try app.flush();
    try std.testing.expectEqual(13, value.signal.observers.items.len);
    try value.set(2);
    try app.flush();
    try std.testing.expectEqual(13, value.signal.observers.items.len);
    try std.testing.expectEqual(1, app.dom.view.render_count);
    try std.testing.expectEqual(2, app.findView("branch").?.render_count);
    for (branch.children) |child| try std.testing.expectEqual(2, child.calls);
}
