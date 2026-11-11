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
        const gallery = ui.hbox().key("gallery").heightPercent(100).padding(16).gap(16);
        const sidebar = gallery.vbox().key("menu").width(180).heightPercent(100).gap(12);
        _ = sidebar.label("Cookbook");
        _ = sidebar.label("ZUI / LVGL SDL2").smallText(true).textColor(0x526475);
        _ = sidebar.label("Examples");
        const menu = sidebar.scroll().key("menu-scroller").height(0).grow(1).gap(6);
        inline for (recipes, 0..) |recipe, index| {
            _ = menu.button(recipe.title)
                .key("page:" ++ recipe.key)
                .widthPercent(100)
                .height(32)
                .smallText(true)
                .selected(selected == index)
                .background(if (selected == index) 0x244b5a else 0xecf0f3)
                .textColor(if (selected == index) 0xffffff else 0x283548)
                .onClick(zui.callback(self, struct {
                fn activate(g: *Gallery) !void {
                    try g.select(index);
                }
            }.activate));
        }
        const panes = gallery.splitter(self.ratio.binding())
            .key("example-panes")
            .width(0)
            .grow(1)
            .heightPercent(100);
        const code = panes.vbox().key("code").gap(10);
        const heading = code.hbox().height(38);
        _ = heading.label("Code").width(0).grow(1);
        _ = heading.button("Reload").key("reload").onClick(zui.callback(self, reload));
        _ = code.labelFmt("{s}.zig", .{page.key}).key("source-file").smallText(true);
        // Changing the key resets source scroll position on recipe navigation.
        const scroller = code.scroll()
            .key(page.key)
            .height(0)
            .grow(1)
            .padding(12)
            .background(0x272822)
            .textColor(0xf8f8f2)
            .smallText(true);
        _ = scroller.label(self.source_text.get(ui)).key("source-code");
        const result = panes.vbox().key("result").gap(10);
        _ = result.label("Result").height(38);
        _ = result.labelFmt("{s}  /  {s}", .{ page.title, page.status() }).smallText(true).widthPercent(100);
        var body = result.scroll().key(page.key).height(0).grow(1).gap(12);
        if (page.content) |declare| {
            declare(&self.model, &body);
            if (page.remaining.len > 0)
                _ = body.labelFmt("Still to port: {s}", .{page.remaining})
                    .smallText(true)
                    .textColor(0x526475)
                    .widthPercent(100);
        } else {
            _ = body.label("Not yet implemented in ZUI").widthPercent(100);
            _ = body.label(page.remaining).widthPercent(100);
        }
    }
};
