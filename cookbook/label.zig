const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    _ = ui.checkbox("Show greeting", model.greeting_visible.binding()).key("greeting-toggle");
    _ = ui.label("Hello World").key("greeting").visible(model.greeting_visible.get(ui));
    _ = ui.label("Color").textColor(0xd3b98b).background(0x1c2a30);
    _ = ui.label("No <b>HTML</b>");
    _ = ui.label("A label can wrap onto several lines when its width is constrained.").widthPercent(100);
}
