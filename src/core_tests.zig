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
    _ = ui.label(&text).key("a");
    text[0] = 'x';
    try snapshot.finish();
    try std.testing.expectEqualStrings("ok", snapshot.root.children.items[0].text);
    _ = ui.button("duplicate").key("a");
    const invalid = ui.grid().columns(0);
    _ = invalid.label("ignored");
    ui.fail(error.LaterError);
    try std.testing.expectEqual(2, snapshot.root.children.items.len);
    try std.testing.expectError(error.DuplicateKey, snapshot.finish());
    try std.testing.expectError(error.DuplicateKey, snapshot.finish());
}

test "invalid containers remain safe and disable previously copied builders" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    const sibling = ui.vbox();
    const invalid = ui.grid().columns(0);
    const nested = invalid.hbox();
    _ = nested.labelFmt("Ignored {d}", .{42});
    _ = sibling.button("also ignored");
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
        const child = ui.vbox();
        _ = child.checkbox("skipped getter", binding);
        _ = child.labelFmt("still safe: {s}", .{text.get(&ui)});
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
    const panes = ui.splitter(ratio.binding());
    _ = panes.label("Only one pane");
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
    const column = ui.vbox().key("column");
    _ = column.checkbox("toggle", state.binding());
    _ = column.textField(text.binding());
    _ = column.labelFmt("Value: {s}", .{text.get(&ui)});
    const row = column.hbox();
    _ = row.button("Action");
    const grid = column.grid().columns(2);
    _ = grid.label("Cell");
    const scroll = column.scroll();
    _ = scroll.label("Scrollable");
    var ratio = State(u8).init(allocator, 50);
    defer ratio.deinit();
    const panes = column.splitter(ratio.binding());
    _ = panes.label("Left");
    _ = panes.label("Right");
    try snapshot.finish();
    try observer.prepare(snapshot.dependencies.items);
    observer.commit(snapshot.dependencies.items);
    try text.set("updated");
}

test "all core allocation failures clean up declarations, text and subscriptions" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "temporary chains and copied handles share a node and own keys and text" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    const ui = snapshot.builder();
    const box = ui.vbox().key("box").padding(12).gap(4);
    var text = [_]u8{ 'o', 'k' };
    var key = [_]u8{ 'i', 'd' };
    const original = box.label(&text).key(&key).visible(false)
        .widthPercent(50).width(120).height(20).heightPercent(75);
    const copy = original;
    _ = copy.visible(true).textColor(0x123456).key("renamed").key(&key);
    text[0] = 'x';
    key[0] = 'x';
    try snapshot.finish();
    try std.testing.expectEqual(1, box.parent.?.children.items.len);
    try std.testing.expectEqual(original.parent, copy.parent);
    const declaration = original.parent.?;
    try std.testing.expectEqualStrings("ok", declaration.text);
    try std.testing.expectEqualStrings("id", declaration.options.key.?);
    try std.testing.expect(declaration.options.visible);
    try std.testing.expectEqual(120, declaration.options.width.?);
    try std.testing.expect(declaration.options.width_percent == null);
    try std.testing.expectEqual(75, declaration.options.height_percent.?);
    try std.testing.expect(declaration.options.height == null);
    try std.testing.expectEqual(0x123456, declaration.options.text_color.?);
    // Reapplying a key must not mistake the same node for a sibling duplicate.
    _ = original.key("id");
    try snapshot.finish();
}

test "a failed modifier disables copies and chains while preserving the first error" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    const ui = snapshot.builder();
    const before = ui.label("kept").width(80);
    const copy = before;
    const invalid = ui.vbox().widthPercent(101).padding(12).visible(false);
    _ = invalid.hbox().label("ignored").key("ignored");
    _ = copy.width(999).key("also ignored");
    _ = ui.labelFmt("ignored {d}", .{10});
    ui.fail(error.LaterFailure);
    try std.testing.expect(invalid.parent == null);
    try std.testing.expectEqual(2, snapshot.root.children.items.len);
    try std.testing.expectEqual(80, before.parent.?.options.width.?);
    try std.testing.expect(before.parent.?.options.key == null);
    try std.testing.expectError(error.InvalidLayout, snapshot.finish());
}

test "leaf handles cannot receive children and virtual Views reject physical modifiers" {
    const Model = struct {
        pub fn content(_: *@This(), ui: *core.Builder) void {
            _ = ui.label("child");
        }
    };
    var model = Model{};
    const leaf_snapshot = try Snapshot.create(std.testing.allocator);
    defer leaf_snapshot.destroy();
    const leaf_ui = leaf_snapshot.builder();
    _ = leaf_ui.label("leaf").label("invalid child");
    try std.testing.expectError(error.InvalidParent, leaf_snapshot.finish());
    const view_snapshot = try Snapshot.create(std.testing.allocator);
    defer view_snapshot.destroy();
    const view_ui = view_snapshot.builder();
    _ = view_ui.view(&model).key("view").visible(false);
    try std.testing.expectError(error.InvalidViewModifier, view_snapshot.finish());
}
