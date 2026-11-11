const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

/// HBox, VBox and the root container, like CPPUI's Box.
pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    const horizontal = node.kind == .row;
    const inverse = node.options.inverse;
    c.lv_obj_set_flex_flow(object, if (horizontal)
        (if (inverse) c.LV_FLEX_FLOW_ROW_REVERSE else c.LV_FLEX_FLOW_ROW)
    else
        (if (inverse) c.LV_FLEX_FLOW_COLUMN_REVERSE else c.LV_FLEX_FLOW_COLUMN));
    // The root scrolls when its content overflows the window.
    if (node.kind != .root) c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
}
