const std = @import("std");
const c = @import("c");
const core = @import("core");
const Node = core.Node;

/// Native state retained across declarations, like the fields CPPUI's LVGL
/// classes move from `prev` in update(). Owned by exactly one Node at a time.
pub const Widget = struct {
    object: ?*c.lv_obj_t = null,
    /// Event user data. It follows the current declaration so callbacks never
    /// see a retired one, and native event lists don't change on redraw.
    observer: ?*Observer = null,
    /// A button's text, or a splitter's divider handle.
    inner: ?*c.lv_obj_t = null,
    /// A Grid's track templates, borrowed by LVGL.
    tracks: ?Tracks = null,
    /// The splitter's first-pane percentage when no binding is declared.
    split_ratio: u8 = 50,
};

pub const Tracks = struct {
    columns: []i32,
    rows: []i32,
};

pub const Observer = struct {
    owner: *Node,
};

pub fn root(node: *Node) *core.Root {
    return node.owner.?.root.?;
}

/// Take over the previous declaration's native state (CPPUI's update(prev)).
pub fn adopt(node: *Node, prev: ?*Node) void {
    const previous = prev orelse return;
    node.ui = previous.ui;
    previous.ui = .{};
    if (node.ui.observer) |observer| observer.owner = node;
}

/// The existing native object, or a new one created in the parent's native.
pub fn object(node: *Node, comptime create: anytype) !*c.lv_obj_t {
    if (node.ui.object) |existing| return existing;
    const parent = node.inner() orelse c.lv_screen_active().?;
    const created = create(parent) orelse return error.NativeCreateFailed;
    errdefer c.lv_obj_delete(created);
    if (node.ui.observer == null) {
        const observer = try node.allocator.create(Observer);
        observer.* = .{ .owner = node };
        node.ui.observer = observer;
    }
    _ = c.lv_obj_add_event_cb(created, event, c.LV_EVENT_ALL, node.ui.observer.?);
    node.ui.object = created;
    return created;
}

fn unobserve(node: *Node) void {
    const observer = node.ui.observer orelse return;
    if (node.ui.object) |native| _ = c.lv_obj_remove_event_cb_with_user_data(native, event, observer);
}

pub fn destroy(node: *Node, direct: bool) void {
    unobserve(node);
    if (node.kind == .splitter) @import("splitter.zig").unobserve(node);
    if (node.ui.object) |native| {
        // LVGL borrows the grid templates until its object is gone.
        if (node.ui.tracks != null and !direct) c.lv_obj_set_grid_dsc_array(native, &empty_track, &empty_track);
        if (direct) c.lv_obj_delete(native);
    }
    release(node);
}

const empty_track = [_]i32{ 0, c.LV_GRID_TEMPLATE_LAST };

/// Free non-native storage that no successor adopted.
pub fn release(node: *Node) void {
    if (node.ui.observer) |observer| node.allocator.destroy(observer);
    if (node.ui.tracks) |tracks| {
        node.allocator.free(tracks.columns);
        node.allocator.free(tracks.rows);
    }
    node.ui = .{};
}

pub fn addChild(_: *Node, index: usize, child: *Node) void {
    if (child.ui.object) |native| c.lv_obj_move_to_index(native, @intCast(index));
}
pub fn removeChild(_: *Node, _: usize, child: *Node) void {
    if (child.ui.object) |native| c.lv_obj_move_to_index(native, -1);
}

pub fn isContainer(kind: core.node.Kind) bool {
    return switch (kind) {
        .root, .column, .row, .grid, .scroll, .splitter => true,
        else => false,
    };
}

/// Layout and style modifiers shared by every widget, applied after the
/// widget's own update like CPPUI's applyOptions().
pub fn applyOptions(node: *Node) void {
    const native = node.ui.object.?;
    const options = node.options;
    const container = isContainer(node.kind);
    if (container) {
        c.lv_obj_set_style_border_width(native, 0, 0);
        c.lv_obj_set_style_radius(native, 0, 0);
        c.lv_obj_set_style_pad_all(native, options.padding, 0);
        c.lv_obj_set_style_pad_row(native, options.gap, 0);
        c.lv_obj_set_style_pad_column(native, options.gap, 0);
    }
    // Spacers and dividers size themselves along their parent's axis.
    if (node.kind != .spacer and node.kind != .divider) {
        const width = if (options.width_percent) |percent| c.lv_pct(percent) else options.width orelse
            (if (container or node.kind == .text_field) c.lv_pct(100) else c.LV_SIZE_CONTENT);
        const height = if (options.height_percent) |percent| c.lv_pct(percent) else options.height orelse (switch (node.kind) {
            .root => c.lv_pct(100),
            .scroll => 200,
            else => c.LV_SIZE_CONTENT,
        });
        c.lv_obj_set_size(native, width, height);
        c.lv_obj_set_flex_grow(native, options.weight);
    }
    c.lv_obj_set_state(native, c.LV_STATE_DISABLED, options.disabled);
    if (options.color) |color| {
        c.lv_obj_set_style_text_color(native, c.lv_color_hex(color), 0);
    } else _ = c.lv_obj_remove_local_style_prop(native, c.LV_STYLE_TEXT_COLOR, 0);
    if (options.bg_color) |color| {
        c.lv_obj_set_style_bg_color(native, c.lv_color_hex(color), 0);
        c.lv_obj_set_style_bg_opa(native, c.LV_OPA_COVER, 0);
    } else if (node.kind != .divider and node.kind != .spacer) {
        _ = c.lv_obj_remove_local_style_prop(native, c.LV_STYLE_BG_COLOR, 0);
        _ = c.lv_obj_remove_local_style_prop(native, c.LV_STYLE_BG_OPA, 0);
    }
    if (options.font_size) |size| {
        c.lv_obj_set_style_text_font(native, font(size), 0);
    } else _ = c.lv_obj_remove_local_style_prop(native, c.LV_STYLE_TEXT_FONT, 0);
    if (options.visible)
        c.lv_obj_remove_flag(native, c.LV_OBJ_FLAG_HIDDEN)
    else
        c.lv_obj_add_flag(native, c.LV_OBJ_FLAG_HIDDEN);
}

/// The nearest compiled Montserrat size (see native/lv_conf.h).
fn font(size: u8) *const c.lv_font_t {
    const fonts = [_]struct { size: u8, font: *const c.lv_font_t }{
        .{ .size = 12, .font = &c.lv_font_montserrat_12 },
        .{ .size = 14, .font = &c.lv_font_montserrat_14 },
        .{ .size = 16, .font = &c.lv_font_montserrat_16 },
        .{ .size = 20, .font = &c.lv_font_montserrat_20 },
        .{ .size = 24, .font = &c.lv_font_montserrat_24 },
    };
    var best = fonts[0];
    for (fonts[1..]) |candidate| {
        if (@abs(@as(i16, candidate.size) - size) < @abs(@as(i16, best.size) - size)) best = candidate;
    }
    return best.font;
}

/// The physical children of a container, flattening virtual Views.
pub fn physicalChildren(node: *Node, out: *std.ArrayListUnmanaged(*Node)) !void {
    for (node.children.items) |child| {
        if (child.is_outoforder) continue;
        if (child.is_virtual) try physicalChildren(child, out) else if (child.ui.object != null) try out.append(node.allocator, child);
    }
}

fn event(raw: ?*c.lv_event_t) callconv(.c) void {
    const e = raw orelse return;
    const observer: *Observer = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
    const node = observer.owner;
    const code = c.lv_event_get_code(e);
    if (code == c.LV_EVENT_DELETE) {
        // Deleted outside ZUI: forget the native and let its View remount it.
        node.ui.object = null;
        node.ui.inner = null;
        core.Root.nativeDeleted(node);
        return;
    }
    const context = root(node);
    if (context.busy) return;
    // Copy every callback/binding before invoking user code. Reconciliation is
    // deferred until dispatch unwinds, including nested native events.
    const native = node.ui.object orelse return;
    const on_click = node.options.on_click;
    const bool_binding = node.bool_binding;
    const text_binding = node.text_binding;
    context.dispatch_depth += 1;
    defer context.dispatch_depth -= 1;
    if (code == c.LV_EVENT_CLICKED) {
        if (on_click) |cb| cb.invoke(cb.context) catch |err| context.report(node, err);
    } else if (code == c.LV_EVENT_VALUE_CHANGED) {
        if (bool_binding) |binding|
            binding.set(c.lv_obj_has_state(native, c.LV_STATE_CHECKED)) catch |err| context.report(node, err);
        if (text_binding) |binding|
            binding.set(std.mem.span(c.lv_textarea_get_text(native))) catch |err| context.report(node, err);
    }
}
