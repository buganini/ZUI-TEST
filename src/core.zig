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

        pub fn get(self: @This(), ui: *Builder) !T {
            if (self.signal) |signal| try ui.track(signal);
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
        pub fn get(self: *Self, ui: *Builder) !T {
            try ui.track(&self.signal);
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
    pub fn get(self: *TextState, ui: *Builder) ![]const u8 {
        try ui.track(&self.signal);
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

pub const Callback = struct {
    context: *anyopaque,
    invoke: *const fn (*anyopaque) anyerror!void,
};

pub fn callback(context: anytype, comptime function: anytype) Callback {
    const T = @TypeOf(context);
    return .{ .context = context, .invoke = struct {
        fn invoke(raw: *anyopaque) !void {
            try function(@as(T, @ptrCast(@alignCast(raw))));
        }
    }.invoke };
}

pub const Kind = enum { root, column, row, grid, scroll, label, button, checkbox, text_field };

pub const Options = struct {
    key: ?[]const u8 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    padding: i32 = 0,
    gap: i32 = 8,
    grow: u8 = 0,
    disabled: bool = false,
    columns: u16 = 2,
    on_click: ?Callback = null,
};

pub const Declaration = struct {
    kind: Kind,
    options: Options,
    text: [:0]const u8,
    checked: bool = false,
    bool_binding: ?Binding(bool) = null,
    text_binding: ?Binding([]const u8) = null,
    children: std.ArrayListUnmanaged(*Declaration) = std.ArrayListUnmanaged(*Declaration).empty,
};

/// Each render owns its declarations, copied keys, copied text and dependencies.
/// Kept alive until the next successful commit; failed builds discard it whole.
pub const Snapshot = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    root: Declaration,
    dependencies: std.ArrayListUnmanaged(*Signal) = std.ArrayListUnmanaged(*Signal).empty,

    pub fn create(allocator: Allocator) !*Snapshot {
        const self = try allocator.create(Snapshot);
        self.* = .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .root = .{ .kind = .root, .options = .{}, .text = "" },
        };
        return self;
    }
    pub fn destroy(self: *Snapshot) void {
        const allocator = self.allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }
    pub fn builder(self: *Snapshot) Builder {
        return .{ .snapshot = self, .parent = &self.root };
    }
};

/// A builder is a handle into one render's arena; never keep it after build().
pub const Builder = struct {
    snapshot: *Snapshot,
    parent: *Declaration,

    pub fn track(self: *Builder, signal: *Signal) !void {
        if (std.mem.indexOfScalar(*Signal, self.snapshot.dependencies.items, signal) == null)
            try self.snapshot.dependencies.append(self.snapshot.arena.allocator(), signal);
    }
    fn add(self: *Builder, kind: Kind, text: []const u8, options: Options) !*Declaration {
        if (options.padding < 0 or options.gap < 0 or
            (options.width != null and options.width.? < 0) or
            (options.height != null and options.height.? < 0)) return error.InvalidLayout;
        if (kind == .grid and options.columns == 0) return error.InvalidLayout;
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        if (options.key) |key| {
            if (key.len == 0) return error.EmptyKey;
            for (self.parent.children.items) |child| {
                if (child.options.key) |other| {
                    if (std.mem.eql(u8, key, other)) return error.DuplicateKey;
                }
            }
        }
        const allocator = self.snapshot.arena.allocator();
        const node = try allocator.create(Declaration);
        const copied_text = try allocator.allocSentinel(u8, text.len, 0);
        @memcpy(copied_text, text);
        node.* = .{ .kind = kind, .options = options, .text = copied_text };
        if (options.key) |key| node.options.key = try allocator.dupe(u8, key);
        try self.parent.children.append(allocator, node);
        return node;
    }
    fn container(self: *Builder, kind: Kind, options: Options) !Builder {
        return .{ .snapshot = self.snapshot, .parent = try self.add(kind, "", options) };
    }
    pub fn vbox(self: *Builder, options: Options) !Builder {
        return self.container(.column, options);
    }
    pub fn hbox(self: *Builder, options: Options) !Builder {
        return self.container(.row, options);
    }
    pub fn scroll(self: *Builder, options: Options) !Builder {
        return self.container(.scroll, options);
    }
    pub fn grid(self: *Builder, options: Options) !Builder {
        return self.container(.grid, options);
    }
    pub fn label(self: *Builder, text: []const u8, options: Options) !void {
        _ = try self.add(.label, text, options);
    }
    pub fn labelFmt(self: *Builder, comptime fmt: []const u8, args: anytype, options: Options) !void {
        const text = try std.fmt.allocPrint(self.snapshot.arena.allocator(), fmt, args);
        try self.label(text, options);
    }
    pub fn button(self: *Builder, text: []const u8, options: Options) !void {
        _ = try self.add(.button, text, options);
    }
    pub fn checkbox(self: *Builder, text: []const u8, binding: Binding(bool), options: Options) !void {
        const value = try binding.get(self);
        const node = try self.add(.checkbox, text, options);
        node.checked = value;
        node.bool_binding = binding;
    }
    pub fn textField(self: *Builder, binding: Binding([]const u8), options: Options) !void {
        const text = try binding.get(self);
        const node = try self.add(.text_field, text, options);
        node.text_binding = binding;
    }
};

pub fn sameIdentity(old: *const Declaration, next: *const Declaration, old_index: usize, next_index: usize) bool {
    if (old.kind != next.kind) return false;
    if (next.options.key) |key|
        return if (old.options.key) |other| std.mem.eql(u8, key, other) else false;
    return old.options.key == null and old_index == next_index;
}

test "conditional dependencies change only on successful commit and writes coalesce" {
    const a = std.testing.allocator;
    var first = State(i32).init(a, 1);
    defer first.deinit();
    var second = State(i32).init(a, 2);
    defer second.deinit();
    var observer = Observer.init(a);
    defer observer.deinit();
    try observer.prepare(&.{&first.signal});
    observer.commit(&.{&first.signal});
    try first.set(1);
    try std.testing.expect(!observer.dirty);
    try first.set(3);
    try first.set(4);
    try std.testing.expect(observer.dirty);
    try observer.prepare(&.{&second.signal});
    observer.commit(&.{&second.signal});
    try first.set(5);
    try std.testing.expect(!observer.dirty);
    try second.set(6);
    try std.testing.expect(observer.dirty);
}

test "mutation during build is rejected before changing value" {
    var state = State(i32).init(std.testing.allocator, 4);
    defer state.deinit();
    build_depth += 1;
    defer build_depth -= 1;
    try std.testing.expectError(error.MutationDuringBuild, state.set(9));
    try std.testing.expectEqual(4, state.peek());
}

test "destroying a signal untracks observers" {
    var signal = Signal.init(std.testing.allocator);
    var observer = Observer.init(std.testing.allocator);
    defer observer.deinit();
    try observer.prepare(&.{&signal});
    observer.commit(&.{&signal});
    signal.deinit();
    try std.testing.expectEqual(0, observer.dependencies.items.len);
}

test "builder owns keys and text and rejects duplicate sibling keys" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    var text = [_]u8{ 'o', 'k' };
    try ui.label(&text, .{ .key = "a" });
    text[0] = 'x';
    try std.testing.expectEqualStrings("ok", snapshot.root.children.items[0].text);
    try std.testing.expectError(error.DuplicateKey, ui.button("duplicate", .{ .key = "a" }));
    try std.testing.expectError(error.InvalidLayout, ui.grid(.{ .columns = 0 }));
}

fn allocationScenario(allocator: Allocator) !void {
    var state = State(bool).init(allocator, true);
    defer state.deinit();
    var text = try TextState.init(allocator, "initial");
    defer text.deinit();
    var observer = Observer.init(allocator);
    defer observer.deinit();
    const snapshot = try Snapshot.create(allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    var column = try ui.vbox(.{ .key = "column" });
    try column.checkbox("toggle", state.binding(), .{});
    try column.textField(text.binding(), .{});
    try observer.prepare(snapshot.dependencies.items);
    observer.commit(snapshot.dependencies.items);
    try text.set("updated");
}

test "all core allocation failures clean up declarations, text and subscriptions" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
