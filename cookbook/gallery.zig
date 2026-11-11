const std = @import("std");
const zui = @import("zui");
const source = @import("source.zig");
pub const recipes = @import("recipes.zig").all;
pub const Model = @import("model.zig").Model;
pub const source_directory = @import("cookbook_options").source_directory;

pub const Gallery = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
    model: Model,
    selected: zui.State(usize),
    ratio: zui.State(u8),
    source_text: zui.TextState,

    pub fn init(a: std.mem.Allocator, io: std.Io, directory: []const u8) !Gallery {
        var model = try Model.init(a);
        errdefer model.deinit();
        const text = try source.load(a, io, directory, recipes[1].key);
        defer a.free(text);
        return .{
            .allocator = a,
            .io = io,
            .directory = directory,
            .model = model,
            .selected = zui.State(usize).init(a, 1),
            .ratio = zui.State(u8).init(a, 50),
            .source_text = try zui.TextState.init(a, text),
        };
    }
    pub fn deinit(self: *Gallery) void {
        self.source_text.deinit();
        self.ratio.deinit();
        self.selected.deinit();
        self.model.deinit();
    }
    pub fn select(self: *Gallery, index: usize) !void {
        if (index >= recipes.len) return error.UnknownRecipe;
        try self.load(index);
        try self.selected.set(index);
    }
    pub fn selectKey(self: *Gallery, key: []const u8) !void {
        for (recipes, 0..) |page, index| {
            if (std.mem.eql(u8, page.key, key)) return self.select(index);
        }
        return error.UnknownRecipe;
    }
    fn load(self: *Gallery, index: usize) !void {
        const text = try source.load(self.allocator, self.io, self.directory, recipes[index].key);
        defer self.allocator.free(text);
        try self.source_text.set(text);
    }
    fn reload(self: *Gallery) !void {
        try self.load(self.selected.peek());
    }

    pub fn content(self: *Gallery, ui: *zui.Builder) void {
        const selected = self.selected.get(ui);
        const page = recipes[selected];
        const gallery = ui.hbox(.{ .gap = 16 }).id("gallery").layout(.{ .height_percent = 100, .padding = 16 });
        const sidebar = gallery.vbox(.{ .gap = 12 }).id("menu").layout(.{ .width = 180, .height_percent = 100 });
        _ = sidebar.label("Cookbook");
        _ = sidebar.label("ZUI / LVGL SDL2").style(.{ .font_size = 12, .color = 0x526475 });
        _ = sidebar.label("Examples");
        const menu = sidebar.scroll(.{}).id("menu-scroller").layout(.{ .height = 0, .weight = 1 })
            .vbox(.{ .gap = 6 });
        inline for (recipes, 0..) |recipe, index| {
            _ = menu.button(recipe.title)
                .id("page:" ++ recipe.key)
                .layout(.{ .width_percent = 100, .height = 32 })
                .style(.{ .font_size = 12, .bg_color = if (selected == index) 0x244b5a else 0xecf0f3, .color = if (selected == index) 0xffffff else 0x283548 })
                .click(zui.callback(self, struct {
                fn activate(g: *Gallery) !void {
                    try g.select(index);
                }
            }.activate));
        }
        const panes = gallery.splitter(.{})
            .id("example-panes")
            .ratio(self.ratio.binding())
            .layout(.{ .width = 0, .weight = 1, .height_percent = 100 });
        const code = panes.vbox(.{ .gap = 10 }).id("code");
        const heading = code.hbox(.{}).layout(.{ .height = 38 });
        _ = heading.label("Code").layout(.{ .width = 0, .weight = 1 });
        _ = heading.button("Reload").id("reload").click(zui.callback(self, reload));
        _ = code.labelFmt("{s}.zig", .{page.key}).id("source-file").style(.{ .font_size = 12 });
        // Changing the key resets source scroll position on recipe navigation.
        const scroller = code.scroll(.{})
            .id(page.key)
            .layout(.{ .height = 0, .weight = 1, .padding = 12 })
            .style(.{ .bg_color = 0x272822, .color = 0xf8f8f2, .font_size = 12 });
        _ = scroller.label(self.source_text.get(ui)).id("source-code");
        const result = panes.vbox(.{ .gap = 10 }).id("result");
        _ = result.label("Result").layout(.{ .height = 38 });
        _ = result.labelFmt("{s}  /  {s}", .{ page.title, page.status() }).style(.{ .font_size = 12 }).layout(.{ .width_percent = 100 });
        var body = result.scroll(.{}).id(page.key).layout(.{ .height = 0, .weight = 1 })
            .vbox(.{ .gap = 12 });
        if (page.content) |declare| {
            declare(&self.model, &body);
            if (page.remaining.len > 0)
                _ = body.labelFmt("Still to port: {s}", .{page.remaining})
                    .style(.{ .font_size = 12, .color = 0x526475 })
                    .layout(.{ .width_percent = 100 });
        } else {
            _ = body.label("Not yet implemented in ZUI").layout(.{ .width_percent = 100 });
            _ = body.label(page.remaining).layout(.{ .width_percent = 100 });
        }
    }
};
