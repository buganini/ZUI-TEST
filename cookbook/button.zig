const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.labelFmt("Selected: {c}", .{model.button_value.get(ui)}).id("button-value");
    const row = ui.hbox(.{});
    _ = row.button("A").id("button-a").click(zui.callback(model, selectA));
    _ = row.button("B").id("button-b").click(zui.callback(model, selectB));
    _ = ui.button("Disabled").id("button-disabled").disabled(true);
    _ = ui.button("Styled").style(.{ .color = 0x244b5a, .bg_color = 0xfff7e6, .font_size = 20 });
}

fn selectA(model: *Model) !void {
    try model.button_value.set('A');
}
fn selectB(model: *Model) !void {
    try model.button_value.set('B');
}
