const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.checkbox("Reverse order", model.inverse_h.binding()).key("hbox-inverse");
    const reverse = model.inverse_h.get(ui);
    _ = ui.label("Default gap: 8 pixels");
    var row = ui.hbox().key("hbox-default");
    items(&row, reverse);
    _ = ui.label("Gap: 20 pixels");
    var spaced = ui.hbox().gap(20);
    items(&spaced, reverse);
    _ = ui.label("The middle label takes the remaining width.").widthPercent(100);
    const weighted = ui.hbox();
    _ = weighted.label("Left");
    _ = weighted.label("Flexible").width(0).grow(1).background(0xfff7e6);
    _ = weighted.label("Right");
}

fn items(row: *zui.Builder, reverse: bool) void {
    const names = [_][]const u8{ "First", "Second", "Third" };
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        _ = row.label(name).key(name);
    }
}
