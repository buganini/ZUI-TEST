const std = @import("std");
const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const count = model.scroll_rows.get(ui);
    const row = ui.hbox(.{});
    _ = row.button("-").id("scroll-remove").disabled(count == 0).click(zui.callback(model, remove));
    _ = row.labelFmt("{d} rows", .{count});
    _ = row.button("+").id("scroll-add").disabled(count == 200).click(zui.callback(model, add));
    const scroll = ui.scroll(.{}).id("scroller").layout(.{ .height = 420, .padding = 8 }).style(.{ .bg_color = 0xf0f3f6 });
    for (0..count) |i| {
        var buffer: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "Row {d}", .{i + 1}) catch |err| {
            ui.fail(err);
            return;
        };
        _ = scroll.label(text).id(text);
    }
}

fn add(model: *Model) !void {
    try model.scroll_rows.set(@min(200, model.scroll_rows.peek() + 1));
}
fn remove(model: *Model) !void {
    try model.scroll_rows.set(model.scroll_rows.peek() -| 1);
}
