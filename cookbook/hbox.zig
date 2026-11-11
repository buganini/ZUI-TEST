const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) !void {
    try ui.checkbox("Reverse order", model.inverse_h.binding(), .{ .key = "hbox-inverse" });
    const reverse = try model.inverse_h.get(ui);
    try ui.label("Default gap: 8 pixels", .{});
    var row = try ui.hbox(.{ .key = "hbox-default" });
    try items(&row, reverse);
    try ui.label("Gap: 20 pixels", .{});
    var spaced = try ui.hbox(.{ .gap = 20 });
    try items(&spaced, reverse);
    try ui.label("The middle label takes the remaining width.", .{ .width_percent = 100 });
    var weighted = try ui.hbox(.{});
    try weighted.label("Left", .{});
    try weighted.label("Flexible", .{ .width = 0, .grow = 1, .background = 0xfff7e6 });
    try weighted.label("Right", .{});
}

fn items(row: *zui.Builder, reverse: bool) !void {
    const names = [_][]const u8{ "First", "Second", "Third" };
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        try row.label(name, .{ .key = name });
    }
}
