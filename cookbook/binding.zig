const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.label("Custom getter / setter");
    const binding = model.external.binding();
    _ = ui.labelFmt("Value: {s}", .{binding.get(ui)}).id("binding-value").layout(.{ .width_percent = 100 });
    _ = ui.textField(binding).id("binding-field");
    _ = ui.textField(binding).id("binding-mirror");
    _ = ui.button("Update external storage").id("binding-update").click(zui.callback(model, update));
    _ = ui.label("Setter log (latest 100 changes)").layout(.{ .width_percent = 100 });
    const log = ui.scroll(.{}).id("binding-log").layout(.{ .height = 280, .padding = 8 }).style(.{ .bg_color = 0xf0f3f6 });
    if (model.external.count == 0) _ = log.label("Edit either field to record a change.").layout(.{ .width_percent = 100 });
    for (0..model.external.count) |index|
        _ = log.label(model.external.log(index)).style(.{ .font_size = 12 });
}

fn update(model: *Model) !void {
    try model.external.binding().set("from external storage");
}
