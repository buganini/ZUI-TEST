const std = @import("std");
const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

pub fn update(node: *Node) !void {
    const created = node.ui.object == null;
    const object = try base.object(node, c.lv_textarea_create);
    if (created) c.lv_textarea_set_one_line(object, true);
    // Preserve caret and selection when a redraw doesn't change the text.
    const current = std.mem.span(c.lv_textarea_get_text(object));
    if (!std.mem.eql(u8, current, node.text)) c.lv_textarea_set_text(object, node.text.ptr);
    c.lv_textarea_set_placeholder_text(object, if (node.options.placeholder) |text| text.ptr else "");
}
