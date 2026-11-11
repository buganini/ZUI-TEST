const std = @import("std");
const zui = @import("zui");
const cookbook = @import("cookbook");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    var selected: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--list")) {
            for (cookbook.recipes) |page| {
                const line = try init.gpa.print("{s} [{s}]: {s}\n", .{ page.key, page.status(), page.remaining });
                defer init.gpa.free(line);
                try std.Io.File.stdout().writeStreamingAll(init.io, line);
            }
            return;
        } else if (std.mem.eql(u8, arg, "--recipe")) {
            selected = args.next() orelse return error.MissingRecipeKey;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try std.Io.File.stdout().writeStreamingAll(init.io, "Usage: zui-cookbook [--list] [--recipe key]\n");
            return;
        } else {
            std.debug.print("Unknown argument: {s}\nUse --help for usage.\n", .{arg});
            return error.UnknownArgument;
        }
    }
    var gallery = try cookbook.Gallery.init(init.gpa, init.io, cookbook.source_directory);
    defer gallery.deinit();
    if (selected) |key| try gallery.selectKey(key);
    const app = try zui.App.create(init.gpa, &gallery, .{
        .title = "Cookbook (LVGL SDL2)",
        .width = 1024,
        .height = 768,
    });
    defer app.destroy();
    try app.run();
}
