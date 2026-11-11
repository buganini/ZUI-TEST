const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_checkbox_create);
    c.lv_checkbox_set_text(object, node.text.ptr);
    c.lv_obj_set_state(object, c.LV_STATE_CHECKED, node.checked);
}
