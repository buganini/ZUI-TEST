const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.labelFmt("Model value 1: {}", .{model.checkbox_one.get(ui)});
    _ = ui.labelFmt("Model value 2: {}", .{model.checkbox_two.get(ui)});
    _ = ui.checkbox("Checkbox 1", model.checkbox_one.binding()).key("checkbox-1");
    _ = ui.checkbox("Mirror of 1", model.checkbox_one.binding()).key("checkbox-1-mirror");
    _ = ui.checkbox("Checkbox 2", model.checkbox_two.binding()).key("checkbox-2");
    _ = ui.checkbox("Disabled mirror", model.checkbox_one.binding())
        .key("checkbox-disabled-mirror")
        .disabled(true);
    _ = ui.checkbox("Disabled unchecked", model.checkbox_disabled.binding())
        .key("checkbox-disabled")
        .disabled(true);
}
