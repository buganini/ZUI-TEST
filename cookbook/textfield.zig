const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const row = ui.hbox(.{});
    _ = row.button("Clear").id("field-clear").click(zui.callback(model, clear));
    _ = row.button("Set text").id("field-set").click(zui.callback(model, set));
    _ = ui.labelFmt("State: {s}", .{model.field_text.get(ui)}).id("field-value").layout(.{ .width_percent = 100 });
    _ = ui.textField(model.field_text.binding()).id("field-model");
    _ = ui.label("A second editor shares the same binding.").layout(.{ .width_percent = 100 });
    _ = ui.textField(model.field_text.binding()).id("field-mirror");
}

fn clear(model: *Model) !void {
    try model.field_text.set("");
}
fn set(model: *Model) !void {
    try model.field_text.set("something");
}
