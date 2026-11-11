const std = @import("std");
const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) void {
    const count = model.scroll_rows.get(ui);
    const row = ui.hbox();
    _ = row.button("-").key("scroll-remove").disabled(count == 0).onClick(zui.callback(model, remove));
    _ = row.labelFmt("{d} rows", .{count});
    _ = row.button("+").key("scroll-add").disabled(count == 200).onClick(zui.callback(model, add));
    const scroll = ui.scroll().key("scroller").height(420).padding(8).background(0xf0f3f6);
    for (0..count) |i| {
        var buffer: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "Row {d}", .{i + 1}) catch |err| {
            ui.fail(err);
            return;
        };
        _ = scroll.label(text).key(text);
    }
}

fn add(model: *Model) !void {
    try model.scroll_rows.set(@min(200, model.scroll_rows.peek() + 1));
}
fn remove(model: *Model) !void {
    try model.scroll_rows.set(model.scroll_rows.peek() -| 1);
}
