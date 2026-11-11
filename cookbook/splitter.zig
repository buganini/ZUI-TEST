const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    ui.label("Drag a divider, or focus it with Tab and use arrow keys.", .{ .width_percent = 100 });
    var vertical = ui.splitter(model.split_vertical.binding(), .{ .key = "example-splitter", .vertical = true, .height = 440 });
    var horizontal = vertical.splitter(model.split_horizontal.binding(), .{ .key = "splitter-horizontal" });
    var first = horizontal.vbox(.{ .padding = 8, .background = 0xfff7e6 });
    first.label("Pane 1", .{ .width_percent = 100 });
    var second = horizontal.vbox(.{ .padding = 8, .background = 0x244b5a, .text_color = 0xfff7e6 });
    second.label("Pane 2", .{ .width_percent = 100 });
    var bottom = vertical.vbox(.{ .padding = 8, .background = 0xf2e6cf });
    bottom.label("Pane 3", .{ .width_percent = 100 });
}
