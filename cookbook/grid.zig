const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) !void {
    try ui.button("Change column count", .{ .key = "grid-columns", .on_click = zui.callback(model, columns) });
    try ui.checkbox("Reverse tiles", model.grid_reverse.binding(), .{ .key = "grid-reverse" });
    const count = try model.grid_columns.get(ui);
    try ui.labelFmt("{d} equal columns; automatic placement", .{count}, .{ .width_percent = 100 });
    var grid = try ui.grid(.{ .key = "example-grid", .columns = count });
    const names = [_][]const u8{ "A", "B", "C", "D", "E" };
    const reverse = try model.grid_reverse.get(ui);
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        try grid.label(name, .{ .key = name, .height = 60, .background = 0x244b5a, .text_color = 0xfff7e6 });
    }
    try grid.textField(model.grid_text.binding(), .{ .key = "grid-editor" });
    try ui.label("Keyed controls keep their native identity during reflow.", .{ .width_percent = 100 });
}

fn columns(model: *Model) !void {
    try model.grid_columns.set(if (model.grid_columns.peek() == 2) 3 else 2);
}
