const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    ui.checkbox("Show greeting", model.greeting_visible.binding(), .{ .key = "greeting-toggle" });
    if (model.greeting_visible.get(ui))
        ui.label("Hello World", .{ .key = "greeting" });
    ui.label("Color", .{ .text_color = 0xd3b98b, .background = 0x1c2a30 });
    ui.label("No <b>HTML</b>", .{});
    ui.label("A label can wrap onto several lines when its width is constrained.", .{ .width_percent = 100 });
}
