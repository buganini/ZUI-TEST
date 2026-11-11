const std = @import("std");
const c = @import("c");
const core = @import("core");

pub const ApplicationOptions = struct {
    title: [:0]const u8 = "ZUI",
    width: i32 = 800,
    height: i32 = 600,
};

/// Owns one SDL2/LVGL host and the root View, like CPPUI's LVGL Application.
/// Models are borrowed.
pub const Application = struct {
    allocator: std.mem.Allocator,
    host: *c.zui_host,
    root: core.Root,
    render_count: usize = 0,

    pub fn create(allocator: std.mem.Allocator, model: anytype, options: ApplicationOptions) !*Application {
        if (options.width <= 0 or options.height <= 0) return error.InvalidWindowSize;
        const self = try allocator.create(Application);
        errdefer allocator.destroy(self);
        const host = c.zui_host_create(options.title, options.width, options.height) orelse return error.HostUnavailable;
        errdefer c.zui_host_destroy(host);
        self.* = .{ .allocator = allocator, .host = host, .root = undefined };
        try self.root.init(allocator, model);
        return self;
    }
    /// Call after run()/pump() returns, never from content or a native callback.
    pub fn destroy(self: *Application) void {
        self.root.deinit();
        c.zui_host_destroy(self.host);
        self.allocator.destroy(self);
    }
    pub fn invalidate(self: *Application) void {
        self.root.invalidate();
    }
    pub fn requestQuit(self: *Application) void {
        c.zui_host_request_close(self.host);
    }
    pub fn flush(self: *Application) !void {
        defer self.render_count = self.root.render_count;
        try self.root.flush();
    }
    pub fn pump(self: *Application) !bool {
        if (c.zui_host_closing(self.host)) return false;
        try self.flush();
        _ = c.zui_host_pump(self.host);
        if (c.zui_host_closing(self.host)) return false;
        try self.flush();
        return true;
    }
    pub fn saveScreenshot(self: *Application, path: [:0]const u8) !void {
        try self.flush();
        c.lv_refr_now(null);
        if (!c.zui_host_save_bmp(self.host, path)) return error.ScreenshotFailed;
    }
    pub fn run(self: *Application) !void {
        while (try self.pump()) c.zui_host_delay(8);
    }
    pub fn findView(self: *Application, id: []const u8) ?*core.View {
        return self.root.findView(id);
    }
    pub fn find(self: *Application, id: []const u8) ?*c.lv_obj_t {
        return self.root.find(id);
    }
};
