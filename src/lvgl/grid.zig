const std = @import("std");
const c = @import("c");
const core = @import("core");
const Node = core.Node;
const base = @import("base.zig");

const initial = [_]i32{ c.LV_GRID_FR(1), c.LV_GRID_TEMPLATE_LAST };

/// Like CPPUI's LVGL Grid: cells are assigned together after the children
/// are reconciled, and tracks are sized from what was placed.
pub fn update(node: *Node) !void {
    const object = try base.object(node, c.lv_obj_create);
    c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
    if (node.ui.tracks == null) c.lv_obj_set_grid_dsc_array(object, &initial, &initial);
}

pub fn postSync(node: *Node) !void {
    const allocator = node.allocator;
    const object = node.ui.object orelse return;
    var children = std.ArrayListUnmanaged(*Node).empty;
    defer children.deinit(allocator);
    try base.physicalChildren(node, &children);
    const declarations = try allocator.alloc(*const Node, children.items.len);
    defer allocator.free(declarations);
    for (children.items, declarations) |child, *slot| slot.* = child;
    const placement = try core.grid.place(allocator, node, declarations);
    defer allocator.free(placement.cells);
    // Equal columns; rows fit their single-row content.
    const columns = try tracks(allocator, @max(1, placement.columns), c.LV_GRID_FR(1));
    errdefer allocator.free(columns);
    const rows = try tracks(allocator, @max(1, placement.rows), 0);
    for (children.items, placement.cells) |child, maybe| {
        const native = child.ui.object.?;
        const cell = maybe orelse continue;
        // Spanning rows don't size content tracks, so those cells stretch.
        const y_align: c.lv_grid_align_t = if (cell.rowspan > 1) c.LV_GRID_ALIGN_STRETCH else c.LV_GRID_ALIGN_START;
        c.lv_obj_set_grid_cell(native, c.LV_GRID_ALIGN_STRETCH, @intCast(cell.column), @intCast(cell.columnspan), y_align, @intCast(cell.row), @intCast(cell.rowspan));
    }
    fitRows(object, rows);
    // Replace the borrowed templates before freeing the old ones.
    c.lv_obj_set_grid_dsc_array(object, columns.ptr, rows.ptr);
    if (node.ui.tracks) |old| {
        allocator.free(old.columns);
        allocator.free(old.rows);
    }
    node.ui.tracks = .{ .columns = columns, .rows = rows };
    c.lv_obj_mark_layout_as_dirty(object);
}

fn tracks(allocator: std.mem.Allocator, count: u32, size: i32) ![]i32 {
    const result = try allocator.alloc(i32, @as(usize, count) + 1);
    @memset(result[0..count], size);
    result[count] = c.LV_GRID_TEMPLATE_LAST;
    return result;
}

/// LVGL's content tracks ignore spanning cells, so rows covered only by
/// spans would collapse. Like CPPUI, size single-row cells first, then share
/// each span's unmet height evenly across its rows.
fn fitRows(object: *c.lv_obj_t, template: []i32) void {
    const rows = template[0 .. template.len - 1];
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
            if (start >= rows.len) continue;
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
}
