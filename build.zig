const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("zui_core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const core_tests = b.addTest(.{ .root_module = core });
    const core_run = b.addRunArtifact(core_tests);
    b.step("test-core", "Test the reactive core without LVGL").dependOn(&core_run.step);

    const lvgl_input = b.option([]const u8, "lvgl-dir", "LVGL 9.6.0 source directory") orelse "deps/lvgl";
    const lvgl_dir: std.Build.LazyPath = if (std.fs.path.isAbsolute(lvgl_input))
        .{ .cwd_relative = lvgl_input }
    else
        b.path(lvgl_input);
    const native_build = b.addSystemCommand(&.{"sh"});
    native_build.addFileArg(b.path("native/build.sh"));
    native_build.addDirectoryArg(b.path("native"));
    native_build.addDirectoryArg(lvgl_dir);
    const native_dir = native_build.addOutputDirectoryArg("native");
    native_build.addArg(if (std.mem.eql(u8, @tagName(optimize), "Debug") or std.mem.eql(u8, @tagName(optimize), "debug")) "Debug" else "RelWithDebInfo");
    // CMake tracks changes inside the user's LVGL checkout on every invocation.
    native_build.has_side_effects = true;
    for ([_][]const u8{ "CMakeLists.txt", "lv_conf.h", "host.h", "host.c", "import.h" }) |file|
        native_build.addFileInput(b.path(b.fmt("native/{s}", .{file})));

    const c = b.addTranslateC(.{
        .root_source_file = b.path("native/import.h"),
        .target = target,
        .optimize = optimize,
    });
    c.addIncludePath(b.path("native"));
    c.addIncludePath(lvgl_dir);
    const cmod = c.createModule();
    const zui = b.addModule("zui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zui.addImport("c", cmod);
    zui.addImport("core", core);
    zui.addObjectFile(native_dir.path(b, "libzui_native.a"));
    zui.addObjectFile(native_dir.path(b, "liblvgl.a"));
    zui.linkSystemLibrary("SDL2", .{});
    zui.linkSystemLibrary("m", .{});

    const app = b.addExecutable(.{ .name = "zui-demo", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zui", .module = zui }},
    }) });
    b.installArtifact(app);
    const run = b.addRunArtifact(app);
    b.step("run", "Run the LVGL counter, form and keyed-list demo").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = zui });
    const test_run = b.addRunArtifact(tests);
    test_run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    test_run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    test_run.setEnvironmentVariable("SDL_RENDER_DRIVER", "software");
    const test_step = b.step("test", "Run core and LVGL integration tests");
    test_step.dependOn(&core_run.step);
    test_step.dependOn(&test_run.step);
    const demo_tests = b.addTest(.{ .root_module = app.root_module });
    const demo_run = b.addRunArtifact(demo_tests);
    demo_run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    demo_run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    demo_run.setEnvironmentVariable("SDL_RENDER_DRIVER", "software");
    test_step.dependOn(&demo_run.step);
}
