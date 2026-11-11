const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_button_create);
    const label = node.ui.inner orelse c.lv_label_create(object) orelse return error.NativeCreateFailed;
    node.ui.inner = label;
    c.lv_label_set_text(label, node.text.ptr);
    c.lv_obj_center(label);
}
