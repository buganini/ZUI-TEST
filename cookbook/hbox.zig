const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const inverse = model.inverse_h.get(ui);
    _ = ui.checkbox("Reverse horizontal order", model.inverse_h.binding()).id("hbox-inverse");
    const spaced = ui.hbox(.{ .inverse = inverse }).id("spacer-row");
    _ = spaced.label("Column 1");
    _ = spaced.divider();
    _ = spaced.spacer().id("row-gap");
    _ = spaced.label("Column 2").id("row-end");
    const weighted = ui.hbox(.{ .inverse = inverse });
    _ = weighted.label("Column 1");
    _ = weighted.divider();
    _ = weighted.label("Column 2").layout(.{ .width = 0, .weight = 1 });
    _ = weighted.divider();
    _ = weighted.label("Column 3");
    _ = ui.divider();
    _ = ui.label("Default gap: 10 pixels");
    items(ui.hbox(.{ .inverse = inverse }));
    _ = ui.divider();
    _ = ui.label("gap=12 pixels");
    items(ui.hbox(.{ .inverse = inverse, .gap = 12 }).id("hbox-gap"));
}

fn items(row: zui.Builder) void {
    for ([_][]const u8{ "First", "Second", "Third" }) |name| _ = row.label(name).id(name);
}
