const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const inverse = model.inverse_v.get(ui);
    _ = ui.checkbox("Reverse vertical order", model.inverse_v.binding()).id("vbox-inverse");
    const rows = ui.vbox(.{ .inverse = inverse });
    _ = rows.label("Row 1");
    _ = rows.divider();
    _ = rows.label("Row 2");
    _ = ui.divider();
    _ = ui.label("Default gap: 10 pixels");
    items(ui.vbox(.{ .inverse = inverse }));
    _ = ui.divider();
    _ = ui.label("gap=12 pixels");
    items(ui.vbox(.{ .inverse = inverse, .gap = 12 }).id("vbox-gap"));
}

fn items(column: zui.Builder) void {
    for ([_][]const u8{ "First", "Second", "Third" }) |name| _ = column.label(name).id(name);
}
