const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    ui.labelFmt("Selected: {c}", .{model.button_value.get(ui)}, .{ .key = "button-value" });
    var row = ui.hbox(.{});
    row.button("A", .{ .key = "button-a", .on_click = zui.callback(model, selectA) });
    row.button("B", .{ .key = "button-b", .on_click = zui.callback(model, selectB) });
    ui.button("Disabled", .{ .key = "button-disabled", .disabled = true });
    ui.button("Styled", .{ .text_color = 0x244b5a, .background = 0xfff7e6 });
}

fn selectA(model: *Model) !void {
    try model.button_value.set('A');
}
fn selectB(model: *Model) !void {
    try model.button_value.set('B');
}
