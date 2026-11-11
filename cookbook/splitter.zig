const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.label("Drag a divider, or focus it with Tab and use arrow keys.").widthPercent(100);
    const vertical = ui.splitter(model.split_vertical.binding())
        .key("example-splitter")
        .vertical(true)
        .height(440);
    const horizontal = vertical.splitter(model.split_horizontal.binding()).key("splitter-horizontal");
    const first = horizontal.vbox().padding(8).background(0xfff7e6);
    _ = first.label("Pane 1").widthPercent(100);
    const second = horizontal.vbox().padding(8).background(0x244b5a).textColor(0xfff7e6);
    _ = second.label("Pane 2").widthPercent(100);
    const bottom = vertical.vbox().padding(8).background(0xf2e6cf);
    _ = bottom.label("Pane 3").widthPercent(100);
}
