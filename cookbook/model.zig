const std = @import("std");
const zui = @import("zui");

pub const Model = struct {
    inverse_h: zui.State(bool),
    inverse_v: zui.State(bool),
    greeting_visible: zui.State(bool),
    button_value: zui.State(u8),
    checkbox_one: zui.State(bool),
    checkbox_two: zui.State(bool),
    checkbox_disabled: zui.State(bool),
    field_text: zui.TextState,
    grid_columns: zui.State(u16),
    grid_reverse: zui.State(bool),
    grid_text: zui.TextState,
    scroll_rows: zui.State(usize),
    split_horizontal: zui.State(u8),
    split_vertical: zui.State(u8),
    external: External,
    pages: @import("views.zig").Pages,

    pub fn init(a: std.mem.Allocator) !Model {
        var field = try zui.TextState.init(a, "1.23");
        errdefer field.deinit();
        var grid = try zui.TextState.init(a, "This editor survives reflow");
        errdefer grid.deinit();
        var pages = try @import("views.zig").Pages.init(a);
        errdefer pages.deinit();
        return .{
            .pages = pages,
            .inverse_h = zui.State(bool).init(a, false),
            .inverse_v = zui.State(bool).init(a, false),
            .greeting_visible = zui.State(bool).init(a, true),
            .button_value = zui.State(u8).init(a, 'A'),
            .checkbox_one = zui.State(bool).init(a, true),
            .checkbox_two = zui.State(bool).init(a, true),
            .checkbox_disabled = zui.State(bool).init(a, false),
            .field_text = field,
            .grid_columns = zui.State(u16).init(a, 2),
            .grid_reverse = zui.State(bool).init(a, false),
            .grid_text = grid,
            .scroll_rows = zui.State(usize).init(a, 100),
            .split_horizontal = zui.State(u8).init(a, 50),
            .split_vertical = zui.State(u8).init(a, 60),
            .external = try External.init(a),
        };
    }

    pub fn deinit(self: *Model) void {
        self.pages.deinit();
        self.external.deinit();
        self.split_vertical.deinit();
        self.split_horizontal.deinit();
        self.scroll_rows.deinit();
        self.grid_text.deinit();
        self.grid_reverse.deinit();
        self.grid_columns.deinit();
        self.field_text.deinit();
        self.checkbox_disabled.deinit();
        self.checkbox_two.deinit();
        self.checkbox_one.deinit();
        self.button_value.deinit();
        self.greeting_visible.deinit();
        self.inverse_v.deinit();
        self.inverse_h.deinit();
    }
};

/// An external model with a pure getter, notifying setter and bounded log.
/// Like State, it must stay at a stable address while its binding is mounted.
pub const External = struct {
    value: []u8,
    signal: zui.Signal,
    logs: [100][160]u8 = undefined,
    lengths: [100]usize = undefined,
    count: usize = 0,
    start: usize = 0,

    fn init(a: std.mem.Allocator) !External {
        return .{ .value = try a.dupe(u8, "test"), .signal = zui.Signal.init(a) };
    }
    fn deinit(self: *External) void {
        self.signal.allocator.free(self.value);
        self.signal.deinit();
    }
    pub fn binding(self: *External) zui.Binding([]const u8) {
        return .{ .context = self, .signal = &self.signal, .read = read, .write = write };
    }
    fn read(raw: *anyopaque) []const u8 {
        const self: *External = @ptrCast(@alignCast(raw));
        return self.value;
    }
    fn write(raw: *anyopaque, value: []const u8) !void {
        const self: *External = @ptrCast(@alignCast(raw));
        if (std.mem.eql(u8, self.value, value)) return;
        const copy = try self.signal.allocator.dupe(u8, value);
        self.signal.allocator.free(self.value);
        self.value = copy;
        const index = (self.start + self.count) % self.logs.len;
        // Keep UTF-8 boundaries intact when shortening long log messages.
        var end = @min(value.len, 140);
        while (end > 0 and end < value.len and value[end] & 0xc0 == 0x80) : (end -= 1) {}
        const line = try std.fmt.bufPrint(&self.logs[index], "set: {s}{s}", .{ value[0..end], if (end < value.len) "..." else "" });
        self.lengths[index] = line.len;
        if (self.count == self.logs.len) self.start = (self.start + 1) % self.logs.len else self.count += 1;
        self.signal.notify();
    }
    pub fn log(self: *const External, index: usize) []const u8 {
        const slot = (self.start + index) % self.logs.len;
        return self.logs[slot][0..self.lengths[slot]];
    }
};
