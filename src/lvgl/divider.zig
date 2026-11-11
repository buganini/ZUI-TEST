const c = @import("c");
const Node = @import("core").Node;
const base = @import("base.zig");

/// A thin line across its HBox/VBox axis.
pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    @import("spacer.zig").plain(object);
    if (node.options.bg_color == null) {
        c.lv_obj_set_style_bg_color(object, c.lv_color_hex(0xc8d0d8), 0);
        c.lv_obj_set_style_bg_opa(object, c.LV_OPA_COVER, 0);
    }
    const horizontal = if (node.dom_parent) |parent| parent.kind == .row else false;
    c.lv_obj_set_size(object, if (horizontal) 1 else c.lv_pct(100), if (horizontal) c.lv_pct(100) else 1);
    c.lv_obj_set_flex_grow(object, 0);
}
