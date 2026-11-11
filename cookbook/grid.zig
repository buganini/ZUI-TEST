const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.button("Change column count").id("grid-columns").click(zui.callback(model, columns));
    _ = ui.checkbox("Reverse tiles", model.grid_reverse.binding()).id("grid-reverse");
    const count = model.grid_columns.get(ui);
    _ = ui.labelFmt("{d} equal columns; automatic placement", .{count}).layout(.{ .width_percent = 100 });
    const grid = ui.grid(.{}).id("example-grid").columns(count);
    const names = [_][]const u8{ "A", "B", "C", "D", "E" };
    const reverse = model.grid_reverse.get(ui);
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        _ = grid.label(name).id(name).layout(.{ .height = 60 }).style(.{ .bg_color = 0x244b5a, .color = 0xfff7e6 });
    }
    _ = grid.textField(model.grid_text.binding()).id("grid-editor");
    _ = ui.label("Keyed controls keep their native identity during reflow.").layout(.{ .width_percent = 100 });
}

fn columns(model: *Model) !void {
    try model.grid_columns.set(if (model.grid_columns.peek() == 2) 3 else 2);
}
