const std = @import("std");
const c = @import("c");
const core = @import("core");
const Allocator = std.mem.Allocator;
const Declaration = core.Node;

/// LVGL widgets for the backend-independent `core.dom.Dom`, like CPPUI's
/// cppui/lvgl/*.hpp and PUI's per-backend packages.
pub const Backend = struct {
    pub const Native = *c.lv_obj_t;
    pub const Parent = *c.lv_obj_t;

    pub const Widget = struct {
        object: *c.lv_obj_t,
        kind: core.node.Kind,
        /// A button's text, or a splitter's divider handle.
        inner: ?*c.lv_obj_t = null,
        layout: ?Layout = null,
        /// The splitter's first-pane percentage when no binding is declared.
        split_ratio: u8 = 50,
        vertical: bool = false,
    };

    /// LVGL keeps pointers to grid templates, so each update allocates them,
    /// along with the cell of each physical child.
    pub const Layout = struct {
        columns: []i32,
        rows: []i32,
        cells: []?core.grid.Cell,
    };

    pub fn rootParent() Parent {
        return c.lv_screen_active().?;
    }
    pub fn parentOf(widget: *Widget) Parent {
        return widget.object;
    }
    pub fn native(widget: *Widget) Native {
        return widget.object;
    }

    pub fn create(mounted: anytype, parent: Parent) !Widget {
        const Events = Callbacks(@TypeOf(mounted.*));
        const declaration = mounted.declaration;
        const object = switch (declaration.kind) {
            .label => c.lv_label_create(parent),
            .button => c.lv_button_create(parent),
            .checkbox => c.lv_checkbox_create(parent),
            .text_field => c.lv_textarea_create(parent),
            else => c.lv_obj_create(parent),
        } orelse return error.NativeCreateFailed;
        errdefer c.lv_obj_delete(object);
        var widget = Widget{ .object = object, .kind = declaration.kind };
        c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_HIDDEN);
        switch (declaration.kind) {
            .button => widget.inner = c.lv_label_create(object) orelse return error.NativeCreateFailed,
            .text_field => c.lv_textarea_set_one_line(object, true),
            .spacer, .divider => {
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_CLICKABLE);
                c.lv_obj_set_style_pad_all(object, 0, 0);
                c.lv_obj_set_style_border_width(object, 0, 0);
                c.lv_obj_set_style_radius(object, 0, 0);
            },
            .splitter => {
                const handle = c.lv_obj_create(object) orelse return error.NativeCreateFailed;
                widget.inner = handle;
                c.lv_obj_remove_flag(handle, c.LV_OBJ_FLAG_SCROLLABLE);
                c.lv_obj_set_style_pad_all(handle, 0, 0);
                c.lv_obj_set_style_border_width(handle, 0, 0);
                c.lv_obj_set_style_radius(handle, 3, 0);
                c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0xa7b4c2), 0);
                c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0x2196f3), c.LV_STATE_FOCUSED);
                c.lv_obj_set_ext_click_area(handle, 4);
                c.lv_group_add_obj(c.lv_group_get_default(), handle);
                _ = c.lv_obj_add_event_cb(handle, Events.splitter, c.LV_EVENT_ALL, mounted);
            },
            else => {},
        }
        _ = c.lv_obj_add_event_cb(object, Events.event, c.LV_EVENT_ALL, mounted);
        return widget;
    }
    pub fn destroy(allocator: Allocator, mounted: anytype) void {
        const Events = Callbacks(@TypeOf(mounted.*));
        const widget = &mounted.widget.?;
        _ = c.lv_obj_remove_event_cb_with_user_data(widget.object, Events.event, mounted);
        c.lv_obj_delete(widget.object);
        forget(allocator, widget);
    }
    /// Release non-native storage after the native object is gone.
    pub fn forget(allocator: Allocator, widget: *Widget) void {
        if (widget.layout) |layout| freeLayout(allocator, layout);
        widget.layout = null;
    }

    pub fn prepareLayout(allocator: Allocator, declaration: *const Declaration, children: []const *const Declaration) !?Layout {
        if (declaration.kind != .grid) return null;
        const placement = try core.grid.place(allocator, declaration, children);
        errdefer allocator.free(placement.cells);
        // Equal columns; rows fit their single-row content.
        const columns = try tracks(allocator, @max(1, placement.columns), c.LV_GRID_FR(1));
        errdefer allocator.free(columns);
        const rows = try tracks(allocator, @max(1, placement.rows), c.LV_GRID_CONTENT);
        return .{ .columns = columns, .rows = rows, .cells = placement.cells };
    }
    fn tracks(allocator: Allocator, count: u32, size: i32) ![]i32 {
        const result = try allocator.alloc(i32, @as(usize, count) + 1);
        @memset(result[0..count], size);
        result[count] = c.LV_GRID_TEMPLATE_LAST;
        return result;
    }
    pub fn freeLayout(allocator: Allocator, layout: Layout) void {
        allocator.free(layout.columns);
        allocator.free(layout.rows);
        allocator.free(layout.cells);
    }

    fn isContainer(kind: core.node.Kind) bool {
        return switch (kind) {
            .root, .column, .row, .grid, .scroll, .splitter => true,
            else => false,
        };
    }

    pub fn update(allocator: Allocator, widget: *Widget, declaration: *const Declaration, layout: ?Layout) void {
        const object = widget.object;
        const options = declaration.options;
        const container = isContainer(declaration.kind);
        if (container) {
            c.lv_obj_set_style_border_width(object, 0, 0);
            c.lv_obj_set_style_radius(object, 0, 0);
            c.lv_obj_set_style_pad_all(object, options.padding, 0);
            c.lv_obj_set_style_pad_row(object, options.gap, 0);
            c.lv_obj_set_style_pad_column(object, options.gap, 0);
            if (declaration.kind == .grid) {
                const next = layout.?;
                c.lv_obj_set_grid_dsc_array(object, next.columns.ptr, next.rows.ptr);
                forget(allocator, widget);
                widget.layout = next;
            } else {
                const horizontal = declaration.kind == .row or (declaration.kind == .splitter and !options.vertical);
                const flow: c.lv_flex_flow_t = if (horizontal)
                    (if (options.inverse) c.LV_FLEX_FLOW_ROW_REVERSE else c.LV_FLEX_FLOW_ROW)
                else
                    (if (options.inverse) c.LV_FLEX_FLOW_COLUMN_REVERSE else c.LV_FLEX_FLOW_COLUMN);
                c.lv_obj_set_flex_flow(object, flow);
            }
            if (declaration.kind == .scroll) {
                var direction: c.lv_dir_t = c.LV_DIR_NONE;
                if (options.scroll_vertical orelse true) direction |= c.LV_DIR_VER;
                if (options.scroll_horizontal orelse true) direction |= c.LV_DIR_HOR;
                c.lv_obj_set_scroll_dir(object, direction);
            } else if (declaration.kind != .root) {
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
            }
        }
        if (declaration.kind == .splitter) {
            widget.vertical = options.vertical;
            if (declaration.split_binding != null) widget.split_ratio = declaration.split_ratio;
        }
        const width = if (options.width_percent) |percent| c.lv_pct(percent) else options.width orelse (if (container or declaration.kind == .text_field) c.lv_pct(100) else c.LV_SIZE_CONTENT);
        const height = if (options.height_percent) |percent| c.lv_pct(percent) else options.height orelse (switch (declaration.kind) {
            .root => c.lv_pct(100),
            .scroll => 200,
            else => c.LV_SIZE_CONTENT,
        });
        // Spacers and dividers are sized along their parent's axis in place().
        if (declaration.kind != .spacer and declaration.kind != .divider) {
            c.lv_obj_set_size(object, width, height);
            c.lv_obj_set_flex_grow(object, options.weight);
        }
        c.lv_obj_set_state(object, c.LV_STATE_DISABLED, options.disabled);
        if (options.color) |color| {
            c.lv_obj_set_style_text_color(object, c.lv_color_hex(color), 0);
        } else _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_TEXT_COLOR, 0);
        if (options.bg_color) |color| {
            c.lv_obj_set_style_bg_color(object, c.lv_color_hex(color), 0);
            c.lv_obj_set_style_bg_opa(object, c.LV_OPA_COVER, 0);
        } else if (declaration.kind == .divider) {
            c.lv_obj_set_style_bg_color(object, c.lv_color_hex(0xc8d0d8), 0);
            c.lv_obj_set_style_bg_opa(object, c.LV_OPA_COVER, 0);
        } else if (declaration.kind == .spacer) {
            c.lv_obj_set_style_bg_opa(object, c.LV_OPA_TRANSP, 0);
        } else {
            _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_BG_COLOR, 0);
            _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_BG_OPA, 0);
        }
        if (options.font_size) |size| {
            c.lv_obj_set_style_text_font(object, font(size), 0);
        } else _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_TEXT_FONT, 0);
        if (declaration.kind == .label) {
            if (options.on_click != null)
                c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_CLICKABLE)
            else
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_CLICKABLE);
        }
        switch (declaration.kind) {
            .label => c.lv_label_set_text(object, declaration.text.ptr),
            .button => {
                c.lv_label_set_text(widget.inner.?, declaration.text.ptr);
                c.lv_obj_center(widget.inner.?);
            },
            .checkbox => {
                c.lv_checkbox_set_text(object, declaration.text.ptr);
                c.lv_obj_set_state(object, c.LV_STATE_CHECKED, declaration.checked);
            },
            .text_field => {
                // Preserve caret and selection when a redraw doesn't change text.
                const current = std.mem.span(c.lv_textarea_get_text(object));
                if (!std.mem.eql(u8, current, declaration.text))
                    c.lv_textarea_set_text(object, declaration.text.ptr);
                c.lv_textarea_set_placeholder_text(object, if (options.placeholder) |text| text.ptr else "");
            },
            .splitter => {
                const vertical = options.vertical;
                c.lv_obj_set_size(widget.inner.?, if (vertical) c.lv_pct(100) else 8, if (vertical) 8 else c.lv_pct(100));
            },
            else => {},
        }
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

    pub fn place(parent: *Widget, declaration: *const Declaration, child: *Widget, index: usize) void {
        const object = child.object;
        c.lv_obj_move_to_index(object, @intCast(index));
        switch (declaration.kind) {
            .splitter => {
                const vertical = parent.vertical;
                c.lv_obj_set_size(object, if (vertical) c.lv_pct(100) else 0, if (vertical) 0 else c.lv_pct(100));
                const ratio = parent.split_ratio;
                c.lv_obj_set_flex_grow(object, if (index == 0) ratio else 100 - ratio);
            },
            .grid => if (parent.layout.?.cells[index]) |cell| {
                // Spanning rows don't size content tracks, so those cells stretch.
                const y_align: c.lv_grid_align_t = if (cell.rowspan > 1) c.LV_GRID_ALIGN_STRETCH else c.LV_GRID_ALIGN_START;
                c.lv_obj_set_grid_cell(object, c.LV_GRID_ALIGN_STRETCH, @intCast(cell.column), @intCast(cell.columnspan), y_align, @intCast(cell.row), @intCast(cell.rowspan));
            } else {
                // Like PUI's backends, a manual Grid leaves out children without a cell.
                c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_HIDDEN);
            },
            else => {},
        }
        // A spacer grows along its box's axis; a divider spans across it.
        const horizontal = declaration.kind == .row;
        if (child.kind == .spacer) {
            c.lv_obj_set_size(object, if (horizontal) 0 else 1, if (horizontal) 1 else 0);
            c.lv_obj_set_flex_grow(object, 1);
        } else if (child.kind == .divider) {
            c.lv_obj_set_size(object, if (horizontal) 1 else c.lv_pct(100), if (horizontal) c.lv_pct(100) else 1);
            c.lv_obj_set_flex_grow(object, 0);
        }
    }
    pub fn finish(widget: *Widget, declaration: *const Declaration) void {
        const object = widget.object;
        if (declaration.kind == .splitter) c.lv_obj_move_to_index(widget.inner.?, 1);
        if (declaration.kind == .grid) fitRows(object, widget.layout.?);
        if (declaration.options.visible)
            c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_HIDDEN)
        else
            c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_HIDDEN);
    }

    /// LVGL's content tracks ignore spanning cells, so rows covered only by
    /// spans would collapse. Like CPPUI, size single-row cells first, then share
    /// each span's unmet height evenly across its rows.
    fn fitRows(object: *c.lv_obj_t, layout: Layout) void {
        const rows = layout.rows[0 .. layout.rows.len - 1];
        @memset(rows, 0);
        const gap = c.lv_obj_get_style_pad_row(object, c.LV_PART_MAIN);
        const count = c.lv_obj_get_child_count(object);
        var span: i32 = 1;
        while (span <= rows.len) : (span += 1) {
            var index: u32 = 0;
            while (index < count) : (index += 1) {
                const child = c.lv_obj_get_child(object, @intCast(index)).?;
                if (c.lv_obj_has_flag(child, c.LV_OBJ_FLAG_HIDDEN) or c.lv_obj_has_flag(child, c.LV_OBJ_FLAG_IGNORE_LAYOUT)) continue;
                if (c.lv_obj_get_style_grid_cell_row_span(child, c.LV_PART_MAIN) != span) continue;
                const start: usize = @intCast(c.lv_obj_get_style_grid_cell_row_pos(child, c.LV_PART_MAIN));
                const covered = rows[start..@min(rows.len, start + @as(usize, @intCast(span)))];
                const height = c.lv_obj_calc_dynamic_height(child, c.LV_STYLE_HEIGHT) +
                    c.lv_obj_get_style_margin_top(child, c.LV_PART_MAIN) + c.lv_obj_get_style_margin_bottom(child, c.LV_PART_MAIN);
                var available: i32 = gap * (span - 1);
                for (covered) |row| available += row;
                var extra: i32 = @max(0, height - available);
                var remaining: i32 = @intCast(covered.len);
                for (covered) |*row| {
                    const share = @divTrunc(extra, remaining);
                    row.* += share;
                    extra -= share;
                    remaining -= 1;
                }
            }
        }
        c.lv_obj_set_grid_dsc_array(object, layout.columns.ptr, layout.rows.ptr);
        c.lv_obj_mark_layout_as_dirty(object);
    }

    fn Callbacks(comptime Mounted: type) type {
        return struct {
            fn event(raw: ?*c.lv_event_t) callconv(.c) void {
                const e = raw orelse return;
                const mounted: *Mounted = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
                const dom = mounted.dom;
                const code = c.lv_event_get_code(e);
                if (code == c.LV_EVENT_DELETE) {
                    dom.nativeDeleted(mounted);
                    return;
                }
                if (dom.busy) return;
                const object = (mounted.widget orelse return).object;
                // Copy every callback/binding before invoking user code. Reconciliation
                // is deferred until dispatch unwinds, including nested native events.
                const declaration = mounted.declaration.*;
                dom.dispatch_depth += 1;
                defer dom.dispatch_depth -= 1;
                if (code == c.LV_EVENT_CLICKED) {
                    if (declaration.options.on_click) |cb| cb.invoke(cb.context) catch |err| dom.report(mounted, err);
                } else if (code == c.LV_EVENT_VALUE_CHANGED) {
                    if (declaration.bool_binding) |binding| {
                        binding.set(c.lv_obj_has_state(object, c.LV_STATE_CHECKED)) catch |err| dom.report(mounted, err);
                    }
                    if (declaration.text_binding) |binding| {
                        binding.set(std.mem.span(c.lv_textarea_get_text(object))) catch |err| dom.report(mounted, err);
                    }
                }
            }

            fn splitter(raw: ?*c.lv_event_t) callconv(.c) void {
                const e = raw orelse return;
                const mounted: *Mounted = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
                const dom = mounted.dom;
                if (dom.busy) return;
                const widget = if (mounted.widget) |*widget| widget else return;
                const declaration = mounted.declaration.*;
                const code = c.lv_event_get_code(e);
                var ratio: i32 = if (declaration.split_binding) |binding|
                    std.math.clamp(binding.read(binding.context), 10, 90)
                else
                    widget.split_ratio;
                if (code == c.LV_EVENT_PRESSING) {
                    const indev = c.lv_indev_active() orelse return;
                    var point: c.lv_point_t = undefined;
                    c.lv_indev_get_point(indev, &point);
                    var area: c.lv_area_t = undefined;
                    c.lv_obj_get_content_coords(widget.object, &area);
                    const vertical = declaration.options.vertical;
                    const size = (if (vertical) area.y2 - area.y1 else area.x2 - area.x1) + 1;
                    if (size <= 0) return;
                    const offset = if (vertical) point.y - area.y1 else point.x - area.x1;
                    ratio = @divTrunc(offset * 100, size);
                } else if (code == c.LV_EVENT_KEY) {
                    const key = c.lv_event_get_key(e);
                    if (key == c.LV_KEY_LEFT or key == c.LV_KEY_UP) ratio -= 5 else if (key == c.LV_KEY_RIGHT or key == c.LV_KEY_DOWN) ratio += 5 else return;
                } else return;
                const next: u8 = @intCast(std.math.clamp(ratio, 10, 90));
                dom.dispatch_depth += 1;
                defer dom.dispatch_depth -= 1;
                if (declaration.split_binding) |binding| {
                    binding.set(next) catch |err| dom.report(mounted, err);
                } else if (next != widget.split_ratio) {
                    widget.split_ratio = next;
                    mounted.owner.invalidate();
                }
            }
        };
    }
};
