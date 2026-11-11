const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) !void {
    try ui.labelFmt("Model value 1: {}", .{try model.checkbox_one.get(ui)}, .{});
    try ui.labelFmt("Model value 2: {}", .{try model.checkbox_two.get(ui)}, .{});
    try ui.checkbox("Checkbox 1", model.checkbox_one.binding(), .{ .key = "checkbox-1" });
    try ui.checkbox("Mirror of 1", model.checkbox_one.binding(), .{ .key = "checkbox-1-mirror" });
    try ui.checkbox("Checkbox 2", model.checkbox_two.binding(), .{ .key = "checkbox-2" });
    try ui.checkbox("Disabled mirror", model.checkbox_one.binding(), .{ .key = "checkbox-disabled-mirror", .disabled = true });
    try ui.checkbox("Disabled unchecked", model.checkbox_disabled.binding(), .{ .key = "checkbox-disabled", .disabled = true });
}
