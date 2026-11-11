const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_label_create);
    c.lv_label_set_text(object, node.text.ptr);
    if (node.options.on_click != null)
        c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_CLICKABLE)
    else
        c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_CLICKABLE);
}
