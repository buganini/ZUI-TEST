const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Like cppui/backend.hpp, core reaches its widgets through a backend chosen
    // at build time: a native-free one for core tests, LVGL for the library.
    const test_core = b.createModule(.{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const test_backend = b.createModule(.{
        .root_source_file = b.path("src/testing/backend.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "core", .module = test_core }},
    });
    test_core.addImport("backend", test_backend);
    const core_tests = b.addTest(.{ .root_module = test_core });
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
    native_build.addArg(if (optimize == .debug) "Debug" else "RelWithDebInfo");
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
    const core = b.addModule("zui_core", .{
        .root_source_file = b.path("src/core.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lvgl = b.createModule(.{
        .root_source_file = b.path("src/lvgl/backend.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "c", .module = cmod },
            .{ .name = "core", .module = core },
        },
    });
    core.addImport("backend", lvgl);
    const zui = b.addModule("zui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zui.addImport("c", cmod);
    zui.addImport("core", core);
    zui.addImport("lvgl", lvgl);
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
    b.step("run-demo", "Run the minimal counter, form and keyed-list demo").dependOn(&run.step);

    const cookbook_options = b.addOptions();
    const source_input = b.option([]const u8, "cookbook-source-dir", "Recipe source directory to read at runtime") orelse "cookbook";
    const source_path = if (std.fs.path.isAbsolute(source_input)) source_input else b.root.joinString(b.allocator, source_input) catch @panic("OOM");
    cookbook_options.addOption([]const u8, "source_directory", b.pathResolve(&.{source_path}));
    const cookbook = b.createModule(.{
        .root_source_file = b.path("cookbook/gallery.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zui", .module = zui }},
    });
    cookbook.addOptions("cookbook_options", cookbook_options);
    const cookbook_imports: []const std.Build.Module.Import = &.{
        .{ .name = "zui", .module = zui },
        .{ .name = "cookbook", .module = cookbook },
    };
    const gallery = b.addExecutable(.{ .name = "zui-cookbook", .root_module = b.createModule(.{
        .root_source_file = b.path("cookbook/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = cookbook_imports,
    }) });
    b.installArtifact(gallery);
    const gallery_run = b.addRunArtifact(gallery);
    gallery_run.addPassthruArgs();
    b.step("run", "Run the LVGL cookbook (--list or --recipe key)").dependOn(&gallery_run.step);

    const capture = b.addExecutable(.{ .name = "zui-capture", .root_module = b.createModule(.{
        .root_source_file = b.path("examples/capture.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "zui", .module = zui }},
    }) });
    const capture_run = b.addRunArtifact(capture);
    capture_run.setCwd(b.path("."));
    const capture_dir = b.addSystemCommand(&.{ "mkdir", "-p", ".build" });
    capture_dir.setCwd(b.path("."));
    capture_run.step.dependOn(&capture_dir.step);
    headless(capture_run);
    const snapshot_step = b.step("snapshot", "Render the cookbook recipes and demo into .build using SDL's dummy driver");
    snapshot_step.dependOn(&capture_run.step);
    const gallery_capture = b.addExecutable(.{ .name = "zui-cookbook-capture", .root_module = b.createModule(.{
        .root_source_file = b.path("cookbook/capture.zig"),
        .target = target,
        .optimize = optimize,
        .imports = cookbook_imports,
    }) });
    const gallery_capture_run = b.addRunArtifact(gallery_capture);
    gallery_capture_run.setCwd(b.path("."));
    gallery_capture_run.step.dependOn(&capture_dir.step);
    headless(gallery_capture_run);
    snapshot_step.dependOn(&gallery_capture_run.step);

    const tests = b.addTest(.{ .root_module = zui, .use_llvm = true });
    const test_run = b.addRunArtifact(tests);
    headless(test_run);
    const test_step = b.step("test", "Run core and LVGL integration tests");
    test_step.dependOn(&core_run.step);
    test_step.dependOn(&test_run.step);
    const demo_tests = b.addTest(.{ .root_module = app.root_module, .use_llvm = true });
    const demo_run = b.addRunArtifact(demo_tests);
    headless(demo_run);
    test_step.dependOn(&demo_run.step);
    const cookbook_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("cookbook/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = cookbook_imports,
    }), .use_llvm = true });
    const cookbook_run = b.addRunArtifact(cookbook_tests);
    headless(cookbook_run);
    test_step.dependOn(&cookbook_run.step);

    const memcheck = b.step("memcheck", "Check LVGL, demo and cookbook tests with Valgrind");
    for ([_]*std.Build.Step.Compile{ tests, demo_tests, cookbook_tests }) |artifact| {
        const check = b.addSystemCommand(&.{ "valgrind", "--quiet", "--leak-check=full", "--show-leak-kinds=definite,indirect,possible", "--errors-for-leak-kinds=definite,indirect,possible", "--error-exitcode=1" });
        check.addArtifactArg(artifact);
        headless(check);
        memcheck.dependOn(&check.step);
    }
}

fn headless(run: *std.Build.Step.Run) void {
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    run.setEnvironmentVariable("SDL_RENDER_DRIVER", "software");
}
