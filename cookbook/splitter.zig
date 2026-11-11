const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn render(model: *Model, ui: *zui.Builder) !void {
    try ui.label("Drag a divider, or focus it with Tab and use arrow keys.", .{ .width_percent = 100 });
    var vertical = try ui.splitter(model.split_vertical.binding(), .{ .key = "example-splitter", .vertical = true, .height = 440 });
    var horizontal = try vertical.splitter(model.split_horizontal.binding(), .{ .key = "splitter-horizontal" });
    var first = try horizontal.vbox(.{ .padding = 8, .background = 0xfff7e6 });
    try first.label("Pane 1", .{ .width_percent = 100 });
    var second = try horizontal.vbox(.{ .padding = 8, .background = 0x244b5a, .text_color = 0xfff7e6 });
    try second.label("Pane 2", .{ .width_percent = 100 });
    var bottom = try vertical.vbox(.{ .padding = 8, .background = 0xf2e6cf });
    try bottom.label("Pane 3", .{ .width_percent = 100 });
}
