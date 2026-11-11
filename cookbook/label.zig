const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.checkbox("Show greeting", model.greeting_visible.binding()).id("greeting-toggle");
    _ = ui.label("Hello World").id("greeting").visible(model.greeting_visible.get(ui));
    _ = ui.label("Color").style(.{ .color = 0xd3b98b, .bg_color = 0x1c2a30, .font_size = 20 });
    _ = ui.label("No <b>HTML</b>");
    _ = ui.label("A label can wrap onto several lines when its width is constrained.").layout(.{ .width_percent = 100 });
}
