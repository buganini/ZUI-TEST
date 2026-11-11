const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    ui.label("Custom getter / setter", .{});
    const binding = model.external.binding();
    ui.labelFmt("Value: {s}", .{binding.get(ui)}, .{ .key = "binding-value", .width_percent = 100 });
    ui.textField(binding, .{ .key = "binding-field" });
    ui.textField(binding, .{ .key = "binding-mirror" });
    ui.button("Update external storage", .{ .key = "binding-update", .on_click = zui.callback(model, update) });
    ui.label("Setter log (latest 100 changes)", .{ .width_percent = 100 });
    var log = ui.scroll(.{ .key = "binding-log", .height = 280, .padding = 8, .background = 0xf0f3f6 });
    if (model.external.count == 0) log.label("Edit either field to record a change.", .{ .width_percent = 100 });
    for (0..model.external.count) |index|
        log.label(model.external.log(index), .{ .small_text = true });
}

fn update(model: *Model) !void {
    try model.external.binding().set("from external storage");
}
