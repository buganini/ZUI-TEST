const std = @import("std");
const c = @import("c");
const core = @import("core");
const Node = core.Node;
const base = @import("base.zig");

/// Two panes and a draggable, focusable handle between them, like CPPUI's
/// Splitter. The handle's native index stays 1; panes keep their DOM order.
pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    const vertical = node.options.vertical;
    c.lv_obj_set_flex_flow(object, if (vertical) c.LV_FLEX_FLOW_COLUMN else c.LV_FLEX_FLOW_ROW);
    c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
    const handle = node.ui.inner orelse try createHandle(node, object);
    c.lv_obj_set_size(handle, if (vertical) c.lv_pct(100) else 8, if (vertical) 8 else c.lv_pct(100));
    if (node.split_binding != null) node.ui.split_ratio = node.split_ratio;
}

fn createHandle(node: *Node, object: *c.lv_obj_t) !*c.lv_obj_t {
    const handle = c.lv_obj_create(object) orelse return error.NativeCreateFailed;
    c.lv_obj_remove_flag(handle, c.LV_OBJ_FLAG_SCROLLABLE);
    c.lv_obj_set_style_pad_all(handle, 0, 0);
    c.lv_obj_set_style_border_width(handle, 0, 0);
    c.lv_obj_set_style_radius(handle, 3, 0);
    c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0xa7b4c2), 0);
    c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0x2196f3), c.LV_STATE_FOCUSED);
    c.lv_obj_set_ext_click_area(handle, 4);
    c.lv_group_add_obj(c.lv_group_get_default(), handle);
    _ = c.lv_obj_add_event_cb(handle, event, c.LV_EVENT_ALL, node.ui.observer.?);
    node.ui.inner = handle;
    return handle;
}

pub fn unobserve(node: *Node) void {
    const handle = node.ui.inner orelse return;
    if (node.ui.observer) |observer| _ = c.lv_obj_remove_event_cb_with_user_data(handle, event, observer);
}

/// Size the panes by ratio and keep the handle between them.
pub fn postSync(node: *Node) !void {
    var panes = std.ArrayListUnmanaged(*Node).empty;
    defer panes.deinit(node.allocator);
    try base.physicalChildren(node, &panes);
    const vertical = node.options.vertical;
    const ratio = node.ui.split_ratio;
    for (panes.items, 0..) |pane, index| {
        const object = pane.ui.object.?;
        c.lv_obj_set_size(object, if (vertical) c.lv_pct(100) else 0, if (vertical) 0 else c.lv_pct(100));
        c.lv_obj_set_flex_grow(object, if (index == 0) ratio else 100 - ratio);
    }
    if (node.ui.inner) |handle| c.lv_obj_move_to_index(handle, 1);
}

fn event(raw: ?*c.lv_event_t) callconv(.c) void {
    const e = raw orelse return;
    const observer: *base.Observer = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
    const node = observer.owner;
    const context = base.root(node);
    if (context.busy) return;
    const object = node.ui.object orelse return;
    const binding = node.split_binding;
    const code = c.lv_event_get_code(e);
    var ratio: i32 = if (binding) |b| std.math.clamp(b.read(b.context), 10, 90) else node.ui.split_ratio;
    if (code == c.LV_EVENT_PRESSING) {
        const indev = c.lv_indev_active() orelse return;
        var point: c.lv_point_t = undefined;
        c.lv_indev_get_point(indev, &point);
        var area: c.lv_area_t = undefined;
        c.lv_obj_get_content_coords(object, &area);
        const vertical = node.options.vertical;
        const size = (if (vertical) area.y2 - area.y1 else area.x2 - area.x1) + 1;
        if (size <= 0) return;
        const offset = if (vertical) point.y - area.y1 else point.x - area.x1;
        ratio = @divTrunc(offset * 100, size);
    } else if (code == c.LV_EVENT_KEY) {
        const key = c.lv_event_get_key(e);
        if (key == c.LV_KEY_LEFT or key == c.LV_KEY_UP) ratio -= 5 else if (key == c.LV_KEY_RIGHT or key == c.LV_KEY_DOWN) ratio += 5 else return;
    } else return;
    const next: u8 = @intCast(std.math.clamp(ratio, 10, 90));
    context.dispatch_depth += 1;
    defer context.dispatch_depth -= 1;
    if (binding) |b| {
        b.set(next) catch |err| context.report(node, err);
    } else if (next != node.ui.split_ratio) {
        node.ui.split_ratio = next;
        node.owner.?.invalidate();
    }
}
