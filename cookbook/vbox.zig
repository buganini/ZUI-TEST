const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.checkbox("Reverse order", model.inverse_v.binding()).key("vbox-inverse");
    const reverse = model.inverse_v.get(ui);
    _ = ui.label("Default gap: 8 pixels");
    var column = ui.vbox().key("vbox-default");
    items(&column, reverse);
    _ = ui.label("Gap: 20 pixels; padding: 12 pixels").widthPercent(100);
    var spaced = ui.vbox().gap(20).padding(12).background(0xfff7e6);
    items(&spaced, reverse);
}

fn items(column: *zui.Builder, reverse: bool) void {
    const names = [_][]const u8{ "First", "Second", "Third" };
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        _ = column.label(name).key(name);
    }
}
