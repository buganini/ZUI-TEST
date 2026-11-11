const std = @import("std");
const zui = @import("zui");
const cookbook = @import("cookbook");

pub fn main(init: std.process.Init) !void {
    var gallery = try cookbook.Gallery.init(init.gpa, init.io, cookbook.source_directory);
    defer gallery.deinit();
    const app = try zui.Application.create(init.gpa, &gallery, .{
        .title = "Cookbook (LVGL SDL2)",
        .width = 1024,
        .height = 768,
    });
    defer app.destroy();
    for (cookbook.recipes, 0..) |page, index| {
        // Include one unported page to exercise its visible fallback.
        if (page.content == null and index != 0) continue;
        try gallery.select(index);
        _ = try app.pump();
        const path = try init.gpa.printSentinel(".build/cookbook-{s}.bmp", .{page.key}, 0);
        defer init.gpa.free(path);
        try app.saveScreenshot(path);
    }
}
