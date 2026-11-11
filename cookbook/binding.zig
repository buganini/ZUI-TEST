const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.label("Custom getter / setter");
    const binding = model.external.binding();
    _ = ui.labelFmt("Value: {s}", .{binding.get(ui)}).key("binding-value").widthPercent(100);
    _ = ui.textField(binding).key("binding-field");
    _ = ui.textField(binding).key("binding-mirror");
    _ = ui.button("Update external storage").key("binding-update").onClick(zui.callback(model, update));
    _ = ui.label("Setter log (latest 100 changes)").widthPercent(100);
    const log = ui.scroll().key("binding-log").height(280).padding(8).background(0xf0f3f6);
    if (model.external.count == 0) _ = log.label("Edit either field to record a change.").widthPercent(100);
    for (0..model.external.count) |index|
        _ = log.label(model.external.log(index)).smallText(true);
}

fn update(model: *Model) !void {
    try model.external.binding().set("from external storage");
}
