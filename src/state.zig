const std = @import("std");
const Allocator = std.mem.Allocator;

// All reactive operations belong to the UI thread.
pub threadlocal var build_depth: usize = 0;
pub fn checkMutation() !void {
    if (build_depth != 0) return error.MutationDuringBuild;
}

pub const Signal = struct {
    allocator: Allocator,
    observers: std.ArrayListUnmanaged(*Observer) = std.ArrayListUnmanaged(*Observer).empty,

    pub fn init(allocator: Allocator) Signal {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Signal) void {
        for (self.observers.items) |observer| {
            if (std.mem.indexOfScalar(*Signal, observer.dependencies.items, self)) |i|
                _ = observer.dependencies.swapRemove(i);
            observer.dirty = true;
        }
        self.observers.deinit(self.allocator);
    }
    pub fn notify(self: *Signal) void {
        for (self.observers.items) |observer| observer.dirty = true;
    }
    fn detach(self: *Signal, observer: *Observer) void {
        if (std.mem.indexOfScalar(*Observer, self.observers.items, observer)) |i|
            _ = self.observers.swapRemove(i);
    }
};

pub const Observer = struct {
    allocator: Allocator,
    dependencies: std.ArrayListUnmanaged(*Signal) = std.ArrayListUnmanaged(*Signal).empty,
    dirty: bool = true,

    pub fn init(allocator: Allocator) Observer {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Observer) void {
        for (self.dependencies.items) |signal| signal.detach(self);
        self.dependencies.deinit(self.allocator);
    }
    // Reserve everything before replacing the mounted tree or its subscriptions.
    pub fn prepare(self: *Observer, next: []const *Signal) !void {
        try self.dependencies.ensureTotalCapacity(self.allocator, next.len);
        for (next) |signal| {
            if (std.mem.indexOfScalar(*Observer, signal.observers.items, self) == null)
                try signal.observers.ensureUnusedCapacity(signal.allocator, 1);
        }
    }
    pub fn commit(self: *Observer, next: []const *Signal) void {
        for (self.dependencies.items) |signal| signal.detach(self);
        self.dependencies.clearRetainingCapacity();
        for (next) |signal| {
            signal.observers.appendAssumeCapacity(self);
            self.dependencies.appendAssumeCapacity(signal);
        }
        self.dirty = false;
    }
};

/// A borrowed context must remain at a stable address until all controls using
/// the binding have been removed. External storage can provide its own Signal.
pub fn Binding(comptime T: type) type {
    return struct {
        context: *anyopaque,
        signal: ?*Signal = null,
        read: *const fn (*anyopaque) T,
        write: *const fn (*anyopaque, T) anyerror!void,

        pub fn get(self: @This(), ui: anytype) T {
            if (self.signal) |signal| ui.track(signal);
            return self.read(self.context);
        }
        pub fn set(self: @This(), value: T) !void {
            try checkMutation();
            try self.write(self.context, value);
        }
    };
}

/// Values are copied shallowly; use TextState for owned, editable text.
/// State and its allocator must outlive all bindings to it and must not move.
pub fn State(comptime T: type) type {
    return struct {
        value: T,
        signal: Signal,
        const Self = @This();

        pub fn init(allocator: Allocator, value: T) Self {
            return .{ .value = value, .signal = Signal.init(allocator) };
        }
        pub fn deinit(self: *Self) void {
            self.signal.deinit();
        }
        pub fn peek(self: *const Self) T {
            return self.value;
        }
        pub fn get(self: *Self, ui: anytype) T {
            ui.track(&self.signal);
            return self.value;
        }
        pub fn set(self: *Self, value: T) !void {
            try checkMutation();
            if (std.meta.eql(self.value, value)) return;
            self.value = value;
            self.signal.notify();
        }
        pub fn binding(self: *Self) Binding(T) {
            return .{ .context = self, .signal = &self.signal, .read = read, .write = write };
        }
        fn read(raw: *anyopaque) T {
            const self: *Self = @ptrCast(@alignCast(raw));
            return self.value;
        }
        fn write(raw: *anyopaque, value: T) !void {
            const self: *Self = @ptrCast(@alignCast(raw));
            try self.set(value);
        }
    };
}

pub const TextState = struct {
    value: []u8,
    signal: Signal,

    pub fn init(allocator: Allocator, text: []const u8) !TextState {
        return .{ .value = try allocator.dupe(u8, text), .signal = Signal.init(allocator) };
    }
    pub fn deinit(self: *TextState) void {
        self.signal.allocator.free(self.value);
        self.signal.deinit();
    }
    pub fn peek(self: *const TextState) []const u8 {
        return self.value;
    }
    pub fn get(self: *TextState, ui: anytype) []const u8 {
        ui.track(&self.signal);
        return self.value;
    }
    pub fn set(self: *TextState, text: []const u8) !void {
        try checkMutation();
        if (std.mem.eql(u8, self.value, text)) return;
        const copy = try self.signal.allocator.dupe(u8, text);
        self.signal.allocator.free(self.value);
        self.value = copy;
        self.signal.notify();
    }
    pub fn binding(self: *TextState) Binding([]const u8) {
        return .{ .context = self, .signal = &self.signal, .read = read, .write = write };
    }
    fn read(raw: *anyopaque) []const u8 {
        const self: *TextState = @ptrCast(@alignCast(raw));
        return self.value;
    }
    fn write(raw: *anyopaque, text: []const u8) !void {
        const self: *TextState = @ptrCast(@alignCast(raw));
        try self.set(text);
    }
};
