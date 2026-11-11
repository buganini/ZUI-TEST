const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    var row = ui.hbox(.{});
    row.button("Clear", .{ .key = "field-clear", .on_click = zui.callback(model, clear) });
    row.button("Set text", .{ .key = "field-set", .on_click = zui.callback(model, set) });
    ui.labelFmt("State: {s}", .{model.field_text.get(ui)}, .{ .key = "field-value", .width_percent = 100 });
    ui.textField(model.field_text.binding(), .{ .key = "field-model" });
    ui.label("A second editor shares the same binding.", .{ .width_percent = 100 });
    ui.textField(model.field_text.binding(), .{ .key = "field-mirror" });
}

fn clear(model: *Model) !void {
    try model.field_text.set("");
}
fn set(model: *Model) !void {
    try model.field_text.set("something");
}
