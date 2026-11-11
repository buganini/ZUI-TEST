const std = @import("std");
const zui = @import("zui");
const Model = @import("model.zig").Model;

// Each Counter has independent subscriptions and stays mounted when hidden.
// Keep the models at stable addresses for as long as their Views are mounted.
pub const Counter = struct {
    name: []const u8,
    count: zui.State(u32),
    text: zui.TextState,

    fn init(a: std.mem.Allocator, name: []const u8) !Counter {
        return .{ .name = name, .count = zui.State(u32).init(a, 0), .text = try zui.TextState.init(a, name) };
    }
    fn deinit(self: *Counter) void {
        self.text.deinit();
        self.count.deinit();
    }
    pub fn content(self: *Counter, ui: *zui.Builder) void {
        _ = ui.labelFmt("Page {s}: {d}", .{ self.name, self.count.get(ui) });
        _ = ui.button("Increment").id(self.name).click(zui.callback(self, increment));
        _ = ui.textField(self.text.binding());
    }
    fn increment(self: *Counter) !void {
        try self.count.set(self.count.peek() + 1);
    }
};

pub const Pages = struct {
    second: zui.State(bool),
    a: Counter,
    b: Counter,
    pub fn init(allocator: std.mem.Allocator) !Pages {
        var first = try Counter.init(allocator, "A");
        errdefer first.deinit();
        return .{ .second = zui.State(bool).init(allocator, false), .a = first, .b = try Counter.init(allocator, "B") };
    }
    pub fn deinit(self: *Pages) void {
        self.b.deinit();
        self.a.deinit();
        self.second.deinit();
    }
};

pub fn content(model: *Model, ui: *zui.Builder) void {
    const pages = &model.pages;
    _ = ui.checkbox("Show page B", pages.second.binding()).id("view-switch");
    const second = pages.second.get(ui);
    const first_page = ui.vbox(.{}).id("view-page-a").visible(!second);
    _ = first_page.subView(&pages.a).id("view-a");
    const second_page = ui.vbox(.{}).id("view-page-b").visible(second);
    _ = second_page.subView(&pages.b).id("view-b");
    _ = ui.label("Switch pages: controls and carets are retained. Each counter updates its own View.")
        .layout(.{ .width_percent = 100 })
        .style(.{ .font_size = 12 });
}
