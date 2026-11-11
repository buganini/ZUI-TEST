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

        pub fn get(self: @This(), ui: *Builder) T {
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
        pub fn get(self: *Self, ui: *Builder) T {
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
    pub fn get(self: *TextState, ui: *Builder) []const u8 {
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

pub const Kind = enum { root, column, row, grid, scroll, splitter, label, button, checkbox, text_field };

pub const Options = struct {
    key: ?[]const u8 = null,
    width: ?i32 = null,
    height: ?i32 = null,
    width_percent: ?u8 = null,
    height_percent: ?u8 = null,
    padding: i32 = 0,
    gap: i32 = 8,
    grow: u8 = 0,
    disabled: bool = false,
    selected: bool = false,
    vertical: bool = false,
    text_color: ?u32 = null,
    background: ?u32 = null,
    small_text: bool = false,
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
    split_binding: ?Binding(u8) = null,
    split_ratio: u8 = 50,
    children: std.ArrayListUnmanaged(*Declaration) = std.ArrayListUnmanaged(*Declaration).empty,
};

/// Each render owns its declarations, copied keys, copied text and dependencies.
/// Kept alive until the next successful commit; failed builds discard it whole.
pub const Snapshot = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    root: Declaration,
    dependencies: std.ArrayListUnmanaged(*Signal) = std.ArrayListUnmanaged(*Signal).empty,
    failure: ?anyerror = null,

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
    fn fail(self: *Snapshot, err: anyerror) void {
        if (self.failure == null) self.failure = err;
    }
    /// Called once content() returns, before preparing subscriptions or widgets.
    /// A failed snapshot remains failed; the next render uses a fresh snapshot.
    pub fn finish(self: *Snapshot) !void {
        if (self.failure) |err| return err;
        validate(&self.root) catch |err| {
            self.fail(err);
            return err;
        };
    }
    fn validate(node: *const Declaration) error{InvalidPaneCount}!void {
        if (node.kind == .splitter and node.children.items.len != 2) return error.InvalidPaneCount;
        for (node.children.items) |child| try validate(child);
    }
};

/// A builder is a handle into one render's arena; never keep it after content().
pub const Builder = struct {
    snapshot: *Snapshot,
    // Failed containers return a valid handle with no parent. All handles share
    // the snapshot's first error, including copies made before the failure.
    parent: ?*Declaration,

    fn active(self: *const Builder) bool {
        return self.parent != null and self.snapshot.failure == null;
    }
    /// Report a custom declaration error without committing a partial tree.
    pub fn fail(self: *Builder, err: anyerror) void {
        self.snapshot.fail(err);
    }
    pub fn track(self: *Builder, signal: *Signal) void {
        if (!self.active()) return;
        if (std.mem.indexOfScalar(*Signal, self.snapshot.dependencies.items, signal) == null)
            self.snapshot.dependencies.append(self.snapshot.arena.allocator(), signal) catch |err| self.fail(err);
    }
    fn add(self: *Builder, kind: Kind, text: []const u8, options: Options) ?*Declaration {
        if (!self.active()) return null;
        return self.addFallible(kind, text, options) catch |err| {
            self.fail(err);
            return null;
        };
    }
    fn addFallible(self: *Builder, kind: Kind, text: []const u8, options: Options) !*Declaration {
        if (options.padding < 0 or options.gap < 0 or
            (options.width != null and options.width.? < 0) or
            (options.height != null and options.height.? < 0)) return error.InvalidLayout;
        if (kind == .grid and options.columns == 0) return error.InvalidLayout;
        if (options.width_percent) |percent| {
            if (percent > 100 or options.width != null) return error.InvalidLayout;
        }
        if (options.height_percent) |percent| {
            if (percent > 100 or options.height != null) return error.InvalidLayout;
        }
        if (std.mem.indexOfScalar(u8, text, 0) != null) return error.EmbeddedNul;
        if (options.key) |key| {
            if (key.len == 0) return error.EmptyKey;
            for (self.parent.?.children.items) |child| {
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
        try self.parent.?.children.append(allocator, node);
        return node;
    }
    fn container(self: *Builder, kind: Kind, options: Options) Builder {
        return .{ .snapshot = self.snapshot, .parent = self.add(kind, "", options) };
    }
    pub fn vbox(self: *Builder, options: Options) Builder {
        return self.container(.column, options);
    }
    pub fn hbox(self: *Builder, options: Options) Builder {
        return self.container(.row, options);
    }
    pub fn scroll(self: *Builder, options: Options) Builder {
        return self.container(.scroll, options);
    }
    pub fn grid(self: *Builder, options: Options) Builder {
        return self.container(.grid, options);
    }
    /// Exactly two child panes. Ratio is a percentage, clamped to 10..90.
    /// Drag the divider or focus it and use the arrow keys to resize.
    pub fn splitter(self: *Builder, ratio: Binding(u8), options: Options) Builder {
        if (!self.active()) return .{ .snapshot = self.snapshot, .parent = null };
        const value = ratio.get(self);
        const panes = self.container(.splitter, options);
        if (panes.parent) |node| {
            node.split_binding = ratio;
            node.split_ratio = std.math.clamp(value, 10, 90);
        }
        return panes;
    }
    pub fn label(self: *Builder, text: []const u8, options: Options) void {
        _ = self.add(.label, text, options);
    }
    pub fn labelFmt(self: *Builder, comptime fmt: []const u8, args: anytype, options: Options) void {
        if (!self.active()) return;
        const text = std.fmt.allocPrint(self.snapshot.arena.allocator(), fmt, args) catch |err| {
            self.fail(err);
            return;
        };
        self.label(text, options);
    }
    pub fn button(self: *Builder, text: []const u8, options: Options) void {
        _ = self.add(.button, text, options);
    }
    pub fn checkbox(self: *Builder, text: []const u8, binding: Binding(bool), options: Options) void {
        if (!self.active()) return;
        const value = binding.get(self);
        const node = self.add(.checkbox, text, options) orelse return;
        node.checked = value;
        node.bool_binding = binding;
    }
    pub fn textField(self: *Builder, binding: Binding([]const u8), options: Options) void {
        if (!self.active()) return;
        const text = binding.get(self);
        const node = self.add(.text_field, text, options) orelse return;
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
    ui.label(&text, .{ .key = "a" });
    text[0] = 'x';
    try snapshot.finish();
    try std.testing.expectEqualStrings("ok", snapshot.root.children.items[0].text);
    ui.button("duplicate", .{ .key = "a" });
    var invalid = ui.grid(.{ .columns = 0 });
    invalid.label("ignored", .{});
    ui.fail(error.LaterError);
    try std.testing.expectEqual(1, snapshot.root.children.items.len);
    try std.testing.expectError(error.DuplicateKey, snapshot.finish());
    try std.testing.expectError(error.DuplicateKey, snapshot.finish());
}

test "invalid containers remain safe and disable previously copied builders" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    var sibling = ui.vbox(.{});
    var invalid = ui.grid(.{ .columns = 0 });
    var nested = invalid.hbox(.{});
    nested.labelFmt("Ignored {d}", .{42}, .{});
    sibling.button("also ignored", .{});
    try std.testing.expect(invalid.parent == null);
    try std.testing.expect(nested.parent == null);
    try std.testing.expectEqual(0, sibling.parent.?.children.items.len);
    try std.testing.expectError(error.InvalidLayout, snapshot.finish());
}

test "tracking allocation failure keeps real state values and suppresses later widget getters" {
    const Probe = struct {
        reads: usize = 0,
        fn read(raw: *anyopaque) bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.reads += 1;
            return true;
        }
        fn write(_: *anyopaque, _: bool) !void {}
    };
    const a = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(a, .{});
    const snapshot = try Snapshot.create(failing.allocator());
    defer snapshot.destroy();
    var state = State(usize).init(a, 3);
    defer state.deinit();
    var text = try TextState.init(a, "real text");
    defer text.deinit();
    var ui = snapshot.builder();
    failing.fail_index = failing.alloc_index;
    const count = state.get(&ui);
    try std.testing.expectEqual(3, count);
    try std.testing.expectEqualStrings("real text", text.get(&ui));
    try std.testing.expectEqual(3, state.binding().get(&ui));
    var probe = Probe{};
    const binding = Binding(bool){ .context = &probe, .read = Probe.read, .write = Probe.write };
    for (0..count) |_| {
        var child = ui.vbox(.{});
        child.checkbox("skipped getter", binding, .{});
        child.labelFmt("still safe: {s}", .{text.get(&ui)}, .{});
    }
    try std.testing.expectEqual(0, probe.reads);
    try std.testing.expectEqual(0, snapshot.root.children.items.len);
    try std.testing.expectError(error.OutOfMemory, snapshot.finish());
}

test "splitter child counts are checked after content declarations finish" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ratio = State(u8).init(std.testing.allocator, 50);
    defer ratio.deinit();
    var ui = snapshot.builder();
    var panes = ui.splitter(ratio.binding(), .{});
    panes.label("Only one pane", .{});
    try std.testing.expectError(error.InvalidPaneCount, snapshot.finish());
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
    var column = ui.vbox(.{ .key = "column" });
    column.checkbox("toggle", state.binding(), .{});
    column.textField(text.binding(), .{});
    column.labelFmt("Value: {s}", .{text.get(&ui)}, .{});
    var row = column.hbox(.{});
    row.button("Action", .{});
    var grid = column.grid(.{ .columns = 2 });
    grid.label("Cell", .{});
    var scroll = column.scroll(.{});
    scroll.label("Scrollable", .{});
    var ratio = State(u8).init(allocator, 50);
    defer ratio.deinit();
    var panes = column.splitter(ratio.binding(), .{});
    panes.label("Left", .{});
    panes.label("Right", .{});
    try snapshot.finish();
    try observer.prepare(snapshot.dependencies.items);
    observer.commit(snapshot.dependencies.items);
    try text.set("updated");
}

test "all core allocation failures clean up declarations, text and subscriptions" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
