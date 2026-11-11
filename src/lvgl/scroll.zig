const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    c.lv_obj_set_flex_flow(object, c.LV_FLEX_FLOW_COLUMN);
    var direction: c.lv_dir_t = c.LV_DIR_NONE;
    if (node.options.scroll_vertical orelse true) direction |= c.LV_DIR_VER;
    if (node.options.scroll_horizontal orelse true) direction |= c.LV_DIR_HOR;
    c.lv_obj_set_scroll_dir(object, direction);
}
