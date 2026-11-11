const std = @import("std");
const zui = @import("zui");
const cookbook = @import("cookbook");
const c = zui.native;
const a = std.testing.allocator;
const io = std.testing.io;

fn click(app: *zui.Application, key: []const u8) !void {
    const object = app.find(key) orelse return error.MissingControl;
    _ = c.lv_obj_send_event(object, c.LV_EVENT_CLICKED, null);
    try app.flush();
}
fn check(app: *zui.Application, key: []const u8, value: bool) !void {
    const object = app.find(key) orelse return error.MissingControl;
    c.lv_obj_set_state(object, c.LV_STATE_CHECKED, value);
    _ = c.lv_obj_send_event(object, c.LV_EVENT_VALUE_CHANGED, null);
    try app.flush();
}
fn text(app: *zui.Application, key: []const u8) []const u8 {
    return std.mem.span(c.lv_label_get_text(app.find(key).?));
}

test "sidebar visits every recipe and runtime source matches the active page" {
    var gallery = try cookbook.Gallery.init(a, io, cookbook.source_directory);
    defer gallery.deinit();
    const app = try zui.Application.create(a, &gallery, .{ .width = 1024, .height = 768 });
    defer app.destroy();
    try app.flush();
    for (cookbook.recipes, 0..) |page, index| {
        const key = try a.print("page:{s}", .{page.key});
        defer a.free(key);
        try click(app, key);
        try std.testing.expectEqual(index, gallery.selected.peek());
        try std.testing.expect(c.lv_color_eq(c.lv_obj_get_style_bg_color(app.find(key).?, c.LV_PART_MAIN), c.lv_color_hex(0x244b5a)));
        const filename = try a.print("{s}.zig", .{page.key});
        defer a.free(filename);
        try std.testing.expectEqualStrings(filename, text(app, "source-file"));
        if (page.content != null) {
            try std.testing.expect(std.mem.indexOf(u8, text(app, "source-code"), "pub fn content") != null);
        } else try std.testing.expect(std.mem.indexOf(u8, text(app, "source-code"), "Unable to read source file:") != null);
    }
    // Both panes remain beside the sidebar at a smaller desktop size.
    c.lv_display_set_resolution(c.lv_display_get_default(), 720, 540);
    c.lv_obj_update_layout(app.find("gallery").?);
    const code = app.find("code").?;
    const result = app.find("result").?;
    try std.testing.expect(c.lv_obj_get_width(code) > 100);
    try std.testing.expect(c.lv_obj_get_width(result) > 100);
    try std.testing.expect(c.lv_obj_get_x(result) > c.lv_obj_get_x(code));
    try std.testing.expect(c.lv_obj_get_height(app.find("menu-scroller").?) < 540);
}

test "recipes bind native controls, preserve keys during reflow and retain model state on navigation" {
    var gallery = try cookbook.Gallery.init(a, io, cookbook.source_directory);
    defer gallery.deinit();
    const app = try zui.Application.create(a, &gallery, .{ .width = 1024, .height = 768 });
    defer app.destroy();
    try app.flush();
    try click(app, "page:button");
    try click(app, "button-b");
    try std.testing.expectEqualStrings("Selected: B", text(app, "button-value"));
    try std.testing.expect(c.lv_obj_has_state(app.find("button-disabled").?, c.LV_STATE_DISABLED));
    try click(app, "page:checkbox");
    try check(app, "checkbox-1", false);
    try std.testing.expect(!c.lv_obj_has_state(app.find("checkbox-1-mirror").?, c.LV_STATE_CHECKED));
    try std.testing.expect(!c.lv_obj_has_state(app.find("checkbox-disabled-mirror").?, c.LV_STATE_CHECKED));
    try click(app, "page:label");
    try check(app, "greeting-toggle", false);
    try std.testing.expect(c.lv_obj_has_flag(app.find("greeting").?, c.LV_OBJ_FLAG_HIDDEN));
    try click(app, "page:textfield");
    c.lv_textarea_set_text(app.find("field-model").?, "user input");
    try app.flush();
    try std.testing.expectEqualStrings("user input", std.mem.span(c.lv_textarea_get_text(app.find("field-mirror").?)));
    try click(app, "page:grid");
    const manual = app.find("example-grid").?;
    c.lv_obj_update_layout(manual);
    const a_tile = app.find("A").?;
    const d_tile = app.find("D").?;
    try std.testing.expectEqual(1, c.lv_obj_get_style_grid_cell_row_pos(app.find("C").?, c.LV_PART_MAIN));
    try std.testing.expectEqual(2, c.lv_obj_get_style_grid_cell_column_span(app.find("B").?, c.LV_PART_MAIN));
    try std.testing.expect(c.lv_obj_get_x(d_tile) > c.lv_obj_get_x(a_tile));
    try std.testing.expectEqual(c.lv_obj_get_height(a_tile), c.lv_obj_get_height(d_tile));
    try click(app, "page:adaptive_grid");
    const editor = app.find("grid-editor").?;
    const tile = app.find("A").?;
    c.lv_textarea_set_cursor_pos(editor, 4);
    try click(app, "grid-columns");
    try check(app, "grid-reverse", true);
    try std.testing.expectEqual(editor, app.find("grid-editor").?);
    try std.testing.expectEqual(4, c.lv_textarea_get_cursor_pos(editor));
    try std.testing.expectEqual(tile, app.find("A").?);
    try std.testing.expectEqualStrings("G\n2x2", std.mem.span(c.lv_label_get_text(c.lv_obj_get_child(app.find("adaptive-grid").?, 0))));
    // Four columns, as in CPPUI's wide layout: F lands on the recipe's 1-based rows.
    try check(app, "grid-reverse", false);
    try click(app, "grid-columns");
    try std.testing.expectEqual(3, c.lv_obj_get_style_grid_cell_row_pos(app.find("F").?, c.LV_PART_MAIN));
    try click(app, "grid-mode");
    try std.testing.expectEqual(2, c.lv_obj_get_style_grid_cell_row_pos(app.find("F").?, c.LV_PART_MAIN));
    try click(app, "grid-mode");
    try std.testing.expectEqual(4, c.lv_obj_get_style_grid_cell_row_pos(app.find("F").?, c.LV_PART_MAIN));
    try check(app, "grid-show-c", false);
    try std.testing.expect(c.lv_obj_has_flag(app.find("C").?, c.LV_OBJ_FLAG_HIDDEN));
    try click(app, "page:scroll");
    const scroller = app.find("scroller").?;
    c.lv_obj_update_layout(scroller);
    c.lv_obj_scroll_to_y(scroller, 80, false);
    try click(app, "scroll-add");
    try std.testing.expectEqual(101, gallery.model.scroll_rows.peek());
    try std.testing.expectEqual(scroller, app.find("scroller").?);
    try std.testing.expectEqual(80, c.lv_obj_get_scroll_y(scroller));
    try click(app, "page:button");
    try std.testing.expectEqualStrings("Selected: B", text(app, "button-value"));
    try click(app, "page:textfield");
    try std.testing.expectEqualStrings("user input", gallery.model.field_text.peek());
}

test "external binding notifies both editors and bounds its setter log" {
    var gallery = try cookbook.Gallery.init(a, io, cookbook.source_directory);
    defer gallery.deinit();
    try gallery.selectKey("binding");
    const app = try zui.Application.create(a, &gallery, .{});
    defer app.destroy();
    try app.flush();
    c.lv_textarea_set_text(app.find("binding-field").?, "native edit");
    try app.flush();
    try std.testing.expectEqualStrings("native edit", std.mem.span(c.lv_textarea_get_text(app.find("binding-mirror").?)));
    const binding = gallery.model.external.binding();
    for (0..105) |index| {
        var buffer: [20]u8 = undefined;
        try binding.set(try std.fmt.bufPrint(&buffer, "change {d}", .{index}));
    }
    try app.flush();
    try std.testing.expectEqual(100, gallery.model.external.count);
    try std.testing.expectEqualStrings("set: change 5", gallery.model.external.log(0));
    try std.testing.expectEqualStrings("set: change 104", gallery.model.external.log(99));
    try std.testing.expectEqualStrings("change 104", std.mem.span(c.lv_textarea_get_text(app.find("binding-field").?)));
}

test "Reload reads disk changes and missing or invalid source stays recoverable" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    try temporary.dir.writeFile(io, .{ .sub_path = "vbox.zig", .data = "// first version\n" });
    var gallery = try cookbook.Gallery.init(a, io, directory);
    defer gallery.deinit();
    const app = try zui.Application.create(a, &gallery, .{});
    defer app.destroy();
    try app.flush();
    try std.testing.expectEqualStrings("// first version\n", text(app, "source-code"));
    try temporary.dir.writeFile(io, .{ .sub_path = "vbox.zig", .data = "// edited without rebuilding\n" });
    try click(app, "reload");
    try std.testing.expectEqualStrings("// edited without rebuilding\n", text(app, "source-code"));
    try temporary.dir.deleteFile(io, "vbox.zig");
    try click(app, "reload");
    try std.testing.expect(std.mem.indexOf(u8, text(app, "source-code"), directory) != null);
    try temporary.dir.writeFile(io, .{ .sub_path = "vbox.zig", .data = "invalid\x00text" });
    try click(app, "reload");
    try std.testing.expect(std.mem.indexOf(u8, text(app, "source-code"), "InvalidSourceText") != null);
    try temporary.dir.writeFile(io, .{ .sub_path = "vbox.zig", .data = "// recovered" });
    try click(app, "reload");
    try std.testing.expectEqualStrings("// recovered", text(app, "source-code"));
}

test "Views recipe updates one counter and retains hidden pages and editor carets" {
    var gallery = try cookbook.Gallery.init(a, io, cookbook.source_directory);
    defer gallery.deinit();
    try gallery.selectKey("views");
    const app = try zui.Application.create(a, &gallery, .{});
    defer app.destroy();
    try app.flush();
    const first = app.findView("view-a").?;
    const second = app.findView("view-b").?;
    const page = app.find("view-page-a").?;
    const editor = c.lv_obj_get_child(page, 2);
    c.lv_textarea_set_cursor_pos(editor, 1);
    try click(app, "A");
    try std.testing.expectEqual(1, gallery.model.pages.a.count.peek());
    try std.testing.expectEqual(1, app.root.view.render_count);
    try std.testing.expectEqual(2, first.render_count);
    try std.testing.expectEqual(1, second.render_count);
    try check(app, "view-switch", true);
    try std.testing.expect(c.lv_obj_has_flag(page, c.LV_OBJ_FLAG_HIDDEN));
    try click(app, "B");
    try check(app, "view-switch", false);
    try std.testing.expectEqual(first, app.findView("view-a").?);
    try std.testing.expectEqual(editor, c.lv_obj_get_child(page, 2));
    try std.testing.expectEqual(1, c.lv_textarea_get_cursor_pos(editor));
    try std.testing.expectEqual(2, first.render_count);
    try std.testing.expectEqual(2, second.render_count);
}
