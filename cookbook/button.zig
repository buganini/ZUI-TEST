const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.labelFmt("Selected: {c}", .{model.button_value.get(ui)}).key("button-value");
    const row = ui.hbox();
    _ = row.button("A").key("button-a").onClick(zui.callback(model, selectA));
    _ = row.button("B").key("button-b").onClick(zui.callback(model, selectB));
    _ = ui.button("Disabled").key("button-disabled").disabled(true);
    _ = ui.button("Styled").textColor(0x244b5a).background(0xfff7e6);
}

fn selectA(model: *Model) !void {
    try model.button_value.set('A');
}
fn selectB(model: *Model) !void {
    try model.button_value.set('B');
}
