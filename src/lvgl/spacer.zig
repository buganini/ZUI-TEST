const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

/// Takes the remaining space along its HBox/VBox axis.
pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    plain(object);
    c.lv_obj_set_style_bg_opa(object, c.LV_OPA_TRANSP, 0);
    const horizontal = if (node.dom_parent) |parent| parent.kind == .row else false;
    c.lv_obj_set_size(object, if (horizontal) 0 else 1, if (horizontal) 1 else 0);
    c.lv_obj_set_flex_grow(object, 1);
}

pub fn plain(object: *c.lv_obj_t) void {
    c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
    c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_CLICKABLE);
    c.lv_obj_set_style_pad_all(object, 0, 0);
    c.lv_obj_set_style_border_width(object, 0, 0);
    c.lv_obj_set_style_radius(object, 0, 0);
}
