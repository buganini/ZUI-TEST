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

    const lvgl_dir = b.pathResolve(&.{b.option([]const u8, "lvgl-dir", "LVGL 9.6.0 source directory") orelse "deps/lvgl"});
    const configure = b.addSystemCommand(&.{ "cmake", "-S" });
    configure.addDirectoryArg(b.path("native"));
    configure.addArg("-B");
    const native_dir = configure.addOutputDirectoryArg("native");
    configure.addArgs(&.{ b.fmt("-DZUI_LVGL_DIR={s}", .{lvgl_dir}), "-DCMAKE_BUILD_TYPE=Debug" });
    const native_build = b.addSystemCommand(&.{ "cmake", "--build" });
    native_build.addDirectoryArg(native_dir);
    native_build.addArgs(&.{ "--parallel", "4" });

    configure.addFileInput(b.path("native/CMakeLists.txt"));
    configure.addFileInput(b.path("native/lv_conf.h"));
    configure.addFileInput(b.path("native/host.h"));
    configure.addFileInput(b.path("native/host.c"));

    const c = b.addTranslateC(.{
        .root_source_file = b.path("native/import.h"),
        .target = target,
        .optimize = optimize,
    });
    c.addIncludePath(b.path("native"));
    c.addIncludePath(.{ .cwd_relative = lvgl_dir });
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
    app.step.dependOn(&native_build.step);
    b.installArtifact(app);
    const run = b.addRunArtifact(app);
    b.step("run", "Run the LVGL counter, form and keyed-list demo").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = zui });
    tests.step.dependOn(&native_build.step);
    const test_run = b.addRunArtifact(tests);
    test_run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    test_run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    test_run.setEnvironmentVariable("SDL_RENDER_DRIVER", "software");
    const test_step = b.step("test", "Run core and LVGL integration tests");
    test_step.dependOn(&core_run.step);
    test_step.dependOn(&test_run.step);
    const demo_tests = b.addTest(.{ .root_module = app.root_module });
    demo_tests.step.dependOn(&native_build.step);
    const demo_run = b.addRunArtifact(demo_tests);
    demo_run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    demo_run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    demo_run.setEnvironmentVariable("SDL_RENDER_DRIVER", "software");
    test_step.dependOn(&demo_run.step);
}
