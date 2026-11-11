const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("node.zig").Node;

/// Backend-independent Grid placement, like CPPUI's grid.hpp and PUI's grid.py.
/// Computed cells never participate in identity.
pub const Cell = struct {
    row: u32,
    column: u32,
    rowspan: u32 = 1,
    columnspan: u32 = 1,
};

pub const Placement = struct {
    /// One entry per physical child in order; null leaves the child unplaced.
    cells: []?Cell,
    columns: u32,
    rows: u32,
};

/// Without `.columns()`, children with both a row and a column are placed
/// where declared and the others are left out. With `.columns(n)`, visible
/// children flow row by row and skip occupied cells:
/// - `dense = null` restarts each search at the previous child's row,
/// - `dense = false` only moves forward,
/// - `dense = true` backfills from the first cell.
/// `expand_children` then grows cells right and down into free space.
pub fn place(allocator: Allocator, grid: *const Node, children: []const *const Node) !Placement {
    const cells = try allocator.alloc(?Cell, children.len);
    errdefer allocator.free(cells);
    @memset(cells, null);
    const options = grid.options;
    var columns: u32 = 0;
    var rows: u32 = 0;
    if (options.columns) |count| {
        columns = count;
        var cursor: usize = 0;
        var previous_row: usize = 0;
        for (children, cells, 0..) |child, *slot, index| {
            if (!child.options.visible) continue;
            const rowspan: u32 = child.options.grid.rowspan orelse 1;
            const span: u32 = @min(columns, child.options.grid.columnspan orelse 1);
            var position: usize = if (options.dense) |dense| (if (dense) 0 else cursor) else previous_row * columns;
            const cell = search: while (true) {
                const row: u32 = @intCast(position / columns);
                const column: u32 = @intCast(position % columns);
                if (column + span > columns) {
                    position = (@as(usize, row) + 1) * columns;
                    continue;
                }
                // Skip to the right edge of the furthest overlapping rectangle.
                var next = position;
                for (cells[0..index]) |maybe| {
                    const other = maybe orelse continue;
                    if (row < other.row + other.rowspan and row + rowspan > other.row and
                        column < other.column + other.columnspan and column + span > other.column)
                        next = @max(next, @as(usize, row) * columns + other.column + other.columnspan);
                }
                if (next == position) break :search Cell{ .row = row, .column = column, .rowspan = rowspan, .columnspan = span };
                position = next;
            };
            cursor = position + span;
            previous_row = cell.row;
            slot.* = cell;
        }
        if (options.expand_children) expand(cells, columns);
    } else {
        for (children, cells) |child, *slot| {
            const declared = child.options.grid;
            // Resolve before assigning: result locations would write `row` early.
            const row = declared.row orelse continue;
            const column = declared.column orelse continue;
            slot.* = .{ .row = row, .column = column, .rowspan = declared.rowspan orelse 1, .columnspan = declared.columnspan orelse 1 };
        }
    }
    for (cells) |maybe| {
        const cell = maybe orelse continue;
        columns = @max(columns, cell.column + cell.columnspan);
        rows = @max(rows, cell.row + cell.rowspan);
    }
    return .{ .cells = cells, .columns = columns, .rows = rows };
}

/// Grow each cell right to the nearest blocking rectangle, then down to the
/// bottom row. Earlier children's expansions already occupy space.
fn expand(cells: []?Cell, columns: u32) void {
    var bottom: u32 = 0;
    for (cells) |maybe| if (maybe) |cell| {
        bottom = @max(bottom, cell.row + cell.rowspan);
    };
    for (cells, 0..) |*maybe, index| {
        const cell = if (maybe.*) |*found| found else continue;
        var right = columns;
        for (cells, 0..) |other_maybe, other_index| {
            if (other_index == index) continue;
            const other = other_maybe orelse continue;
            if (other.column >= cell.column + cell.columnspan and
                other.row < cell.row + cell.rowspan and other.row + other.rowspan > cell.row)
                right = @min(right, other.column);
        }
        cell.columnspan = right - cell.column;
        var end = bottom;
        for (cells, 0..) |other_maybe, other_index| {
            if (other_index == index) continue;
            const other = other_maybe orelse continue;
            if (other.row >= cell.row + cell.rowspan and
                other.column < cell.column + cell.columnspan and other.column + other.columnspan > cell.column)
                end = @min(end, other.row);
        }
        cell.rowspan = end - cell.row;
    }
}
