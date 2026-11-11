const std = @import("std");
const zui = @import("zui");
const c = zui.native;
const keys = [_][]const u8{ "item-1", "item-2", "item-3", "item-4", "item-5" };

pub const Demo = struct {
    count: zui.State(i32),
    show: zui.State(bool),
    name: zui.TextState,
    length: zui.State(usize),
    reversed: zui.State(bool),
    items: [keys.len]zui.TextState,

    pub fn init(allocator: std.mem.Allocator) !Demo {
        var self: Demo = .{
            .count = zui.State(i32).init(allocator, 0),
            .show = zui.State(bool).init(allocator, true),
            .name = try zui.TextState.init(allocator, "Zig"),
            .length = zui.State(usize).init(allocator, 3),
            .reversed = zui.State(bool).init(allocator, false),
            .items = undefined,
        };
        errdefer self.name.deinit();
        var initialized: usize = 0;
        errdefer for (self.items[0..initialized]) |*item| item.deinit();
        for (&self.items, keys) |*item, key| {
            item.* = try zui.TextState.init(allocator, key);
            initialized += 1;
        }
        return self;
    }
    pub fn deinit(self: *Demo) void {
        for (&self.items) |*item| item.deinit();
        self.reversed.deinit();
        self.length.deinit();
        self.name.deinit();
        self.show.deinit();
        self.count.deinit();
    }
    pub fn content(self: *Demo, ui: *zui.Builder) void {
        const page = ui.vbox(.{ .gap = 16 }).id("page").layout(.{ .padding = 20 });
        _ = page.label("ZUI / Zig + LVGL");
        const counter = page.hbox(.{});
        _ = counter.button("-").id("decrement").click(zui.callback(self, decrement));
        _ = counter.labelFmt("Count: {d}", .{self.count.get(ui)}).id("count").layout(.{ .width = 140 });
        _ = counter.button("+").id("increment").click(zui.callback(self, increment));

        _ = page.checkbox("Show greeting", self.show.binding()).id("show");
        const form = page.grid(.{}).columns(2, .{});
        _ = form.label("Your name");
        _ = form.textField(self.name.binding()).id("name");
        if (self.show.get(ui))
            _ = page.labelFmt("Hello, {s}!", .{self.name.get(ui)}).id("greeting");

        const length = self.length.get(ui);
        const reversed = self.reversed.get(ui);
        const actions = page.hbox(.{});
        _ = actions.button("Add row").id("add").disabled(length == keys.len).click(zui.callback(self, add));
        _ = actions.button("Remove row")
            .id("remove")
            .disabled(length == 0)
            .click(zui.callback(self, remove));
        _ = actions.button("Reverse").id("reverse").click(zui.callback(self, reverse));
        _ = page.label("Edit a row, then reverse: the same editor is retained.");
        const list = page.scroll(.{}).id("list").layout(.{ .height = 210 });
        for (0..length) |index| {
            const i = if (reversed) length - 1 - index else index;
            const row = list.hbox(.{}).id(keys[i]);
            _ = row.labelFmt("Row {d}", .{i + 1}).layout(.{ .width = 100 });
            _ = row.textField(self.items[i].binding()).layout(.{ .width = 360 });
        }
    }
    fn increment(self: *Demo) !void {
        try self.count.set(self.count.peek() + 1);
    }
    fn decrement(self: *Demo) !void {
        try self.count.set(self.count.peek() - 1);
    }
    fn add(self: *Demo) !void {
        try self.length.set(@min(keys.len, self.length.peek() + 1));
    }
    fn remove(self: *Demo) !void {
        try self.length.set(self.length.peek() -| 1);
    }
    fn reverse(self: *Demo) !void {
        try self.reversed.set(!self.reversed.peek());
    }
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();
    var demo = try Demo.init(allocator);
    defer demo.deinit();
    const app = try zui.Application.create(allocator, &demo, .{ .title = "ZUI — Counter, Form and Keyed List" });
    defer app.destroy();
    try app.run();
}

test "the complete demo renders, edits and reorders actual LVGL controls" {
    var demo = try Demo.init(std.testing.allocator);
    defer demo.deinit();
    const app = try zui.Application.create(std.testing.allocator, &demo, .{});
    defer app.destroy();
    try std.testing.expect(try app.pump());
    _ = c.lv_obj_send_event(app.find("increment").?, c.LV_EVENT_CLICKED, null);
    c.lv_textarea_set_text(app.find("name").?, "LVGL");
    try app.flush();
    try std.testing.expectEqual(1, demo.count.peek());
    try std.testing.expectEqualStrings("Hello, LVGL!", std.mem.span(c.lv_label_get_text(app.find("greeting").?)));
    const row = app.find("item-1").?;
    const editor = c.lv_obj_get_child(row, 1);
    c.lv_textarea_set_text(editor, "retained editor");
    _ = c.lv_obj_send_event(app.find("reverse").?, c.LV_EVENT_CLICKED, null);
    try app.flush();
    try std.testing.expectEqual(row, app.find("item-1").?);
    try std.testing.expectEqual(editor, c.lv_obj_get_child(app.find("item-1").?, 1));
    try std.testing.expectEqualStrings("retained editor", demo.items[0].peek());
    _ = c.lv_obj_send_event(app.find("add").?, c.LV_EVENT_CLICKED, null);
    try app.flush();
    try std.testing.expect(app.find("item-4") != null);
    _ = c.lv_obj_send_event(app.find("remove").?, c.LV_EVENT_CLICKED, null);
    try app.flush();
    try std.testing.expect(app.find("item-4") == null);
    c.zui_host_push_quit();
    try std.testing.expect(!(try app.pump()));
}
