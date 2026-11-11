const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const row = ui.hbox();
    _ = row.button("Clear").key("field-clear").onClick(zui.callback(model, clear));
    _ = row.button("Set text").key("field-set").onClick(zui.callback(model, set));
    _ = ui.labelFmt("State: {s}", .{model.field_text.get(ui)}).key("field-value").widthPercent(100);
    _ = ui.textField(model.field_text.binding()).key("field-model");
    _ = ui.label("A second editor shares the same binding.").widthPercent(100);
    _ = ui.textField(model.field_text.binding()).key("field-mirror");
}

fn clear(model: *Model) !void {
    try model.field_text.set("");
}
fn set(model: *Model) !void {
    try model.field_text.set("something");
}
