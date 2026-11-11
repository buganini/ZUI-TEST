const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.label("Drag a divider, or focus it with Tab and use arrow keys.").layout(.{ .width_percent = 100 });
    const vertical = ui.splitter(.{ .vertical = true })
        .id("example-splitter")
        .ratio(model.split_vertical.binding())
        .layout(.{ .height = 440 });
    const horizontal = vertical.splitter(.{}).id("splitter-horizontal").ratio(model.split_horizontal.binding());
    const first = horizontal.vbox(.{}).layout(.{ .padding = 8 }).style(.{ .bg_color = 0xfff7e6 });
    _ = first.label("Pane 1").layout(.{ .width_percent = 100 });
    const second = horizontal.vbox(.{}).layout(.{ .padding = 8 }).style(.{ .bg_color = 0x244b5a, .color = 0xfff7e6 });
    _ = second.label("Pane 2").layout(.{ .width_percent = 100 });
    const bottom = vertical.vbox(.{}).layout(.{ .padding = 8 }).style(.{ .bg_color = 0xf2e6cf });
    _ = bottom.label("Pane 3").layout(.{ .width_percent = 100 });
}
