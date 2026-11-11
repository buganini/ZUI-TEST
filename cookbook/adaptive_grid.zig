const zui = @import("zui");
const Model = @import("model.zig").Model;

const Tile = struct { name: []const u8, rows: u16, columns: u16, background: u32, foreground: u32 };
const tiles = [_]Tile{
    .{ .name = "A", .rows = 2, .columns = 1, .background = 0x244b5a, .foreground = 0xfff7e6 },
    .{ .name = "B", .rows = 1, .columns = 1, .background = 0xa84a3a, .foreground = 0xfff7e6 },
    .{ .name = "C", .rows = 3, .columns = 2, .background = 0xd97b35, .foreground = 0x1c2a30 },
    .{ .name = "D", .rows = 3, .columns = 1, .background = 0xf2e6cf, .foreground = 0x1c2a30 },
    .{ .name = "E", .rows = 1, .columns = 2, .background = 0x8fa38a, .foreground = 0x1c2a30 },
    .{ .name = "F", .rows = 1, .columns = 1, .background = 0x366c91, .foreground = 0xfff7e6 },
    .{ .name = "G", .rows = 2, .columns = 2, .background = 0xd3b98b, .foreground = 0x1c2a30 },
};
const modes = [_][]const u8{ "Ordered", "Dense", "Forward" };

pub fn content(model: *Model, ui: *zui.Builder) void {
    // The gallery's result pane already scrolls.
    const body = ui.*;
    const count = model.grid_columns.get(ui);
    const mode = model.grid_mode.get(ui);
    _ = body.labelFmt("Adaptive Grid: {d} columns (labels: rows x cols).", .{count});
    _ = body.label("Watch blue F (original order; C shown):\nOrdered -> row 4 | Dense -> row 3 | Forward -> row 5");
    const buttons = body.hbox(.{});
    _ = buttons.button("Change column count").id("grid-columns").click(zui.callback(model, columns));
    _ = buttons.button("Next mode").id("grid-mode").click(zui.callback(model, nextMode));
    _ = body.labelFmt("Mode: {s}", .{modes[mode]}).id("grid-mode-label");
    const controls = body.hbox(.{});
    _ = controls.checkbox("Show C", model.grid_show_c.binding()).id("grid-show-c");
    _ = controls.checkbox("Expand children", model.grid_expand.binding()).id("grid-expand");
    _ = controls.checkbox("Reverse tiles", model.grid_reverse.binding()).id("grid-reverse");
    const dense: ?bool = if (mode == 0) null else mode == 1;
    const grid = body.grid(.{ .gap = 8 }).id("adaptive-grid").layout(.{ .width_percent = 100 })
        .columns(count, .{ .dense = dense, .expand_children = model.grid_expand.get(ui) });
    const reverse = model.grid_reverse.get(ui);
    const show_c = model.grid_show_c.get(ui);
    for (0..tiles.len) |index| {
        const tile = tiles[if (reverse) tiles.len - 1 - index else index];
        _ = grid.labelFmt("{s}\n{d}x{d}", .{ tile.name, tile.rows, tile.columns })
            .id(tile.name)
            .gridCell(.{ .rowspan = tile.rows, .columnspan = tile.columns })
            .visible(tile.name[0] != 'C' or show_c)
            .style(.{ .bg_color = tile.background, .color = tile.foreground })
            .layout(.{ .padding = 6, .height = tile.rows * 60 });
    }
    _ = grid.textField(model.grid_text.binding()).id("grid-editor").gridCell(.{ .columnspan = count });
}

fn columns(model: *Model) !void {
    const count = model.grid_columns.peek();
    try model.grid_columns.set(if (count == 4) 1 else count + 1);
}
fn nextMode(model: *Model) !void {
    try model.grid_mode.set((model.grid_mode.peek() + 1) % modes.len);
}
