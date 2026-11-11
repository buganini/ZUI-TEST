const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn render(model: *Model, ui: *zui.Builder) !void {
    var row = try ui.hbox(.{});
    try row.button("Clear", .{ .key = "field-clear", .on_click = zui.callback(model, clear) });
    try row.button("Set text", .{ .key = "field-set", .on_click = zui.callback(model, set) });
    try ui.labelFmt("State: {s}", .{try model.field_text.get(ui)}, .{ .key = "field-value", .width_percent = 100 });
    try ui.textField(model.field_text.binding(), .{ .key = "field-model" });
    try ui.label("A second editor shares the same binding.", .{ .width_percent = 100 });
    try ui.textField(model.field_text.binding(), .{ .key = "field-mirror" });
}

fn clear(model: *Model) !void {
    try model.field_text.set("");
}
fn set(model: *Model) !void {
    try model.field_text.set("something");
}
