const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn render(model: *Model, ui: *zui.Builder) !void {
    try ui.label("Custom getter / setter", .{});
    const binding = model.external.binding();
    try ui.labelFmt("Value: {s}", .{try binding.get(ui)}, .{ .key = "binding-value", .width_percent = 100 });
    try ui.textField(binding, .{ .key = "binding-field" });
    try ui.textField(binding, .{ .key = "binding-mirror" });
    try ui.button("Update external storage", .{ .key = "binding-update", .on_click = zui.callback(model, update) });
    try ui.label("Setter log (latest 100 changes)", .{ .width_percent = 100 });
    var log = try ui.scroll(.{ .key = "binding-log", .height = 280, .padding = 8, .background = 0xf0f3f6 });
    if (model.external.count == 0) try log.label("Edit either field to record a change.", .{ .width_percent = 100 });
    for (0..model.external.count) |index|
        try log.label(model.external.log(index), .{ .small_text = true });
}

fn update(model: *Model) !void {
    try model.external.binding().set("from external storage");
}
