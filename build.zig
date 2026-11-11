const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("zui_core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{ .root_module = core });
    const run = b.addRunArtifact(tests);
    b.step("test-core", "Test the reactive core without LVGL").dependOn(&run.step);
    b.step("test", "Run tests").dependOn(&run.step);
}
