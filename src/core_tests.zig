const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const State = core.State;
const TextState = core.TextState;
const Signal = core.Signal;
const Observer = core.Observer;
const Binding = core.Binding;
const Snapshot = core.Snapshot;

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
    core.state.build_depth += 1;
    defer core.state.build_depth -= 1;
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
