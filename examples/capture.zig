const std = @import("std");
const zui = @import("zui");
const Demo = @import("main.zig").Demo;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();
    var demo = try Demo.init(allocator);
    defer demo.deinit();
    const app = try zui.App.create(allocator, &demo, .{});
    defer app.destroy();
    _ = try app.pump();
    try app.saveScreenshot(".build/demo.bmp");
}
