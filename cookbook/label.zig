const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn render(model: *Model, ui: *zui.Builder) !void {
    try ui.checkbox("Show greeting", model.greeting_visible.binding(), .{ .key = "greeting-toggle" });
    if (try model.greeting_visible.get(ui))
        try ui.label("Hello World", .{ .key = "greeting" });
    try ui.label("Color", .{ .text_color = 0xd3b98b, .background = 0x1c2a30 });
    try ui.label("No <b>HTML</b>", .{});
    try ui.label("A label can wrap onto several lines when its width is constrained.", .{ .width_percent = 100 });
}
