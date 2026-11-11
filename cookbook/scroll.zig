const std = @import("std");
const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) !void {
    const count = try model.scroll_rows.get(ui);
    var row = try ui.hbox(.{});
    try row.button("-", .{ .key = "scroll-remove", .disabled = count == 0, .on_click = zui.callback(model, remove) });
    try row.labelFmt("{d} rows", .{count}, .{});
    try row.button("+", .{ .key = "scroll-add", .disabled = count == 200, .on_click = zui.callback(model, add) });
    var scroll = try ui.scroll(.{ .key = "scroller", .height = 420, .padding = 8, .background = 0xf0f3f6 });
    for (0..count) |i| {
        var buffer: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buffer, "Row {d}", .{i + 1});
        try scroll.label(text, .{ .key = text });
    }
}

fn add(model: *Model) !void {
    try model.scroll_rows.set(@min(200, model.scroll_rows.peek() + 1));
}
fn remove(model: *Model) !void {
    try model.scroll_rows.set(model.scroll_rows.peek() -| 1);
}
