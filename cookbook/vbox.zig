const zui = @import("zui");
const Model = @import("model.zig").Model;

pub fn content(model: *Model, ui: *zui.Builder) !void {
    try ui.checkbox("Reverse order", model.inverse_v.binding(), .{ .key = "vbox-inverse" });
    const reverse = try model.inverse_v.get(ui);
    try ui.label("Default gap: 8 pixels", .{});
    var column = try ui.vbox(.{ .key = "vbox-default" });
    try items(&column, reverse);
    try ui.label("Gap: 20 pixels; padding: 12 pixels", .{ .width_percent = 100 });
    var spaced = try ui.vbox(.{ .gap = 20, .padding = 12, .background = 0xfff7e6 });
    try items(&spaced, reverse);
}

fn items(column: *zui.Builder, reverse: bool) !void {
    const names = [_][]const u8{ "First", "Second", "Third" };
    for (0..names.len) |index| {
        const name = names[if (reverse) names.len - 1 - index else index];
        try column.label(name, .{ .key = name });
    }
}
