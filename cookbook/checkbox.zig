const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    ui.labelFmt("Model value 1: {}", .{model.checkbox_one.get(ui)}, .{});
    ui.labelFmt("Model value 2: {}", .{model.checkbox_two.get(ui)}, .{});
    ui.checkbox("Checkbox 1", model.checkbox_one.binding(), .{ .key = "checkbox-1" });
    ui.checkbox("Mirror of 1", model.checkbox_one.binding(), .{ .key = "checkbox-1-mirror" });
    ui.checkbox("Checkbox 2", model.checkbox_two.binding(), .{ .key = "checkbox-2" });
    ui.checkbox("Disabled mirror", model.checkbox_one.binding(), .{ .key = "checkbox-disabled-mirror", .disabled = true });
    ui.checkbox("Disabled unchecked", model.checkbox_disabled.binding(), .{ .key = "checkbox-disabled", .disabled = true });
}
