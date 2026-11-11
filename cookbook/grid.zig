const zui = @import("zui");
const Model = @import("model.zig").Model;

const Tile = struct { name: []const u8, row: u16, column: u16, rows: u16, columns: u16, background: u32, foreground: u32 };
const tiles = [_]Tile{
    .{ .name = "A", .row = 0, .column = 0, .rows = 2, .columns = 1, .background = 0x244b5a, .foreground = 0xfff7e6 },
    .{ .name = "B", .row = 0, .column = 1, .rows = 1, .columns = 2, .background = 0xa84a3a, .foreground = 0xfff7e6 },
    .{ .name = "C", .row = 1, .column = 1, .rows = 1, .columns = 1, .background = 0xd97b35, .foreground = 0x1c2a30 },
    .{ .name = "D", .row = 1, .column = 2, .rows = 2, .columns = 1, .background = 0xf2e6cf, .foreground = 0x1c2a30 },
    .{ .name = "E", .row = 2, .column = 0, .rows = 1, .columns = 2, .background = 0x8fa38a, .foreground = 0x1c2a30 },
};

pub fn content(_: *Model, ui: *zui.Builder) void {
    _ = ui.label("Manual Grid: tile coordinates and spans are explicit.");
    const grid = ui.grid(.{}).id("example-grid").layout(.{ .width_percent = 100 });
    for (tiles) |tile| {
        _ = grid.labelFmt("{s}\nrow={d}, column={d}\nspan={d} x {d}", .{ tile.name, tile.row, tile.column, tile.rows, tile.columns })
            .id(tile.name)
            .gridCell(.{ .row = tile.row, .column = tile.column, .rowspan = tile.rows, .columnspan = tile.columns })
            .style(.{ .bg_color = tile.background, .color = tile.foreground })
            .layout(.{ .padding = 8, .height = tile.rows * 60 });
    }
}
