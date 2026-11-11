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

    pub fn build(self: *Gallery, ui: *zui.Builder) !void {
        const selected = try self.selected.get(ui);
        const page = recipes[selected];
        var gallery = try ui.hbox(.{ .key = "gallery", .height_percent = 100, .padding = 16, .gap = 16 });
        var sidebar = try gallery.vbox(.{ .key = "menu", .width = 180, .height_percent = 100, .gap = 12 });
        try sidebar.label("Cookbook", .{});
        try sidebar.label("ZUI / LVGL SDL2", .{ .small_text = true, .text_color = 0x526475 });
        try sidebar.label("Examples", .{});
        var menu = try sidebar.scroll(.{ .key = "menu-scroller", .height = 0, .grow = 1, .gap = 6 });
        inline for (recipes, 0..) |recipe, index| {
            try menu.button(recipe.title, .{
                .key = "page:" ++ recipe.key,
                .width_percent = 100,
                .height = 32,
                .small_text = true,
                .selected = selected == index,
                .background = if (selected == index) 0x244b5a else 0xecf0f3,
                .text_color = if (selected == index) 0xffffff else 0x283548,
                .on_click = zui.callback(self, struct {
                    fn activate(g: *Gallery) !void {
                        try g.select(index);
                    }
                }.activate),
            });
        }
        var panes = try gallery.splitter(self.ratio.binding(), .{ .key = "example-panes", .width = 0, .grow = 1, .height_percent = 100 });
        var code = try panes.vbox(.{ .key = "code", .gap = 10 });
        var heading = try code.hbox(.{ .height = 38 });
        try heading.label("Code", .{ .width = 0, .grow = 1 });
        try heading.button("Reload", .{ .key = "reload", .on_click = zui.callback(self, reload) });
        try code.labelFmt("{s}.zig", .{page.key}, .{ .key = "source-file", .small_text = true });
        // Changing the key resets source scroll position on recipe navigation.
        var scroller = try code.scroll(.{ .key = page.key, .height = 0, .grow = 1, .padding = 12, .background = 0x272822, .text_color = 0xf8f8f2, .small_text = true });
        try scroller.label(try self.source_text.get(ui), .{ .key = "source-code" });
        var result = try panes.vbox(.{ .key = "result", .gap = 10 });
        try result.label("Result", .{ .height = 38 });
        try result.labelFmt("{s}  /  {s}", .{ page.title, page.status() }, .{ .small_text = true, .width_percent = 100 });
        var body = try result.scroll(.{ .key = page.key, .height = 0, .grow = 1, .gap = 12 });
        if (page.render) |render| {
            try render(&self.model, &body);
            if (page.remaining.len > 0)
                try body.labelFmt("Still to port: {s}", .{page.remaining}, .{ .small_text = true, .text_color = 0x526475, .width_percent = 100 });
        } else {
            try body.label("Not yet implemented in ZUI", .{ .width_percent = 100 });
            try body.label(page.remaining, .{ .width_percent = 100 });
        }
    }
};
