const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("core.zig");
const State = core.State;
const TextState = core.TextState;
const Signal = core.Signal;
const Observer = core.Observer;
const Binding = core.Binding;
const View = core.View;
const Backend = core.Node.Backend;

const Empty = struct {
    pub fn content(_: *@This(), _: *core.Builder) void {}
};
var empty_model = Empty{};

/// Declarations outside content(): a detached View and its build context,
/// standing in for the scope stack CPPUI's tests construct nodes under.
const Snapshot = struct {
    allocator: Allocator,
    view: *View,
    build: core.node.Build,

    fn create(allocator: Allocator) !*Snapshot {
        const self = try allocator.create(Snapshot);
        errdefer allocator.destroy(self);
        const view = try allocator.create(View);
        view.* = View.init(core.Node.init(allocator, .view), core.view.Content.init(&empty_model));
        self.* = .{ .allocator = allocator, .view = view, .build = .{ .allocator = allocator, .view = view } };
        return self;
    }
    fn destroy(self: *Snapshot) void {
        self.build.dependencies.deinit(self.allocator);
        core.dom.recurDelete(&self.view.node, true);
        self.allocator.destroy(self);
    }
    fn builder(self: *Snapshot) core.Builder {
        return .{ .build = &self.build, .parent = &self.view.node };
    }
    fn finish(self: *Snapshot) !void {
        if (self.build.failure) |err| return err;
        for (self.view.node.children.items) |child| View.validate(child) catch |err| {
            self.build.fail(err);
            return err;
        };
    }
};

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

test "builder owns ids and text and rejects duplicate sibling keys" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    var text = [_]u8{ 'o', 'k' };
    _ = ui.label(&text).id("a");
    text[0] = 'x';
    try snapshot.finish();
    try std.testing.expectEqualStrings("ok", snapshot.view.node.children.items[0].text);
    _ = ui.button("duplicate").id("a");
    const invalid = ui.grid(.{}).columns(0, .{});
    _ = invalid.label("ignored");
    ui.fail(error.LaterError);
    try std.testing.expectEqual(2, snapshot.view.node.children.items.len);
    try std.testing.expectError(error.DuplicateId, snapshot.finish());
    try std.testing.expectError(error.DuplicateId, snapshot.finish());
}

test "invalid containers remain safe and disable previously copied builders" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ui = snapshot.builder();
    const sibling = ui.vbox(.{});
    const invalid = ui.grid(.{}).columns(0, .{});
    const nested = invalid.hbox(.{});
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
        const child = ui.vbox(.{});
        _ = child.checkbox("skipped getter", binding);
        _ = child.labelFmt("still safe: {s}", .{text.get(&ui)});
    }
    try std.testing.expectEqual(0, probe.reads);
    try std.testing.expectEqual(0, snapshot.view.node.children.items.len);
    try std.testing.expectError(error.OutOfMemory, snapshot.finish());
}

test "splitter child counts are checked after content declarations finish" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    var ratio = State(u8).init(std.testing.allocator, 50);
    defer ratio.deinit();
    var ui = snapshot.builder();
    const panes = ui.splitter(.{}).ratio(ratio.binding());
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
    const column = ui.vbox(.{}).id("column");
    _ = column.checkbox("toggle", state.binding());
    _ = column.textField(text.binding());
    _ = column.labelFmt("Value: {s}", .{text.get(&ui)});
    const row = column.hbox(.{});
    _ = row.button("Action");
    const grid = column.grid(.{}).columns(2, .{});
    _ = grid.label("Cell");
    const scroll = column.scroll(.{});
    _ = scroll.label("Scrollable");
    var ratio = State(u8).init(allocator, 50);
    defer ratio.deinit();
    const panes = column.splitter(.{}).ratio(ratio.binding());
    _ = panes.label("Left");
    _ = panes.label("Right");
    try snapshot.finish();
    try observer.prepare(snapshot.build.dependencies.items);
    observer.commit(snapshot.build.dependencies.items);
    try text.set("updated");
}

test "all core allocation failures clean up declarations, text and subscriptions" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "temporary chains and copied handles share a node and own ids and text" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    const ui = snapshot.builder();
    const box = ui.vbox(.{ .gap = 4 }).id("box").layout(.{ .padding = 12 });
    var text = [_]u8{ 'o', 'k' };
    var key = [_]u8{ 'i', 'd' };
    const original = box.label(&text).id(&key).visible(false)
        .layout(.{ .width_percent = 50 }).layout(.{ .width = 120 })
        .layout(.{ .height = 20 }).layout(.{ .height_percent = 75 });
    const copy = original;
    _ = copy.visible(true).style(.{ .color = 0x123456 }).id("renamed").id(&key);
    text[0] = 'x';
    key[0] = 'x';
    try snapshot.finish();
    try std.testing.expectEqual(1, box.parent.?.children.items.len);
    try std.testing.expectEqual(original.parent, copy.parent);
    const declaration = original.parent.?;
    try std.testing.expectEqualStrings("ok", declaration.text);
    try std.testing.expectEqualStrings("id", declaration.options.id.?);
    try std.testing.expect(declaration.options.visible);
    try std.testing.expectEqual(120, declaration.options.width.?);
    try std.testing.expect(declaration.options.width_percent == null);
    try std.testing.expectEqual(75, declaration.options.height_percent.?);
    try std.testing.expect(declaration.options.height == null);
    try std.testing.expectEqual(0x123456, declaration.options.color.?);
    // Reapplying an id must not mistake the same node for a sibling duplicate.
    _ = original.id("id");
    try snapshot.finish();
}

test "a failed modifier disables copies and chains while preserving the first error" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    const ui = snapshot.builder();
    const before = ui.label("kept").layout(.{ .width = 80 });
    const copy = before;
    const invalid = ui.vbox(.{}).layout(.{ .width_percent = 101, .padding = 12 }).visible(false);
    _ = invalid.hbox(.{}).label("ignored").id("ignored");
    _ = copy.layout(.{ .width = 999 }).id("also ignored");
    _ = ui.labelFmt("ignored {d}", .{10});
    ui.fail(error.LaterFailure);
    try std.testing.expect(invalid.parent == null);
    try std.testing.expectEqual(2, snapshot.view.node.children.items.len);
    try std.testing.expectEqual(80, before.parent.?.options.width.?);
    try std.testing.expect(before.parent.?.options.id == null);
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
    _ = view_ui.subView(&model).id("view").visible(false);
    try std.testing.expectError(error.InvalidViewModifier, view_snapshot.finish());
}

test "PUI-style layout, style and container options set only the given fields" {
    const snapshot = try Snapshot.create(std.testing.allocator);
    defer snapshot.destroy();
    const ui = snapshot.builder();
    const row = ui.hbox(.{ .inverse = true, .gap = 4 });
    const grid = ui.grid(.{});
    const label = row.label("styled")
        .layout(.{ .width = 40, .weight = 2 })
        .layout(.{ .padding = 3 })
        .style(.{ .color = 0x123456 })
        .style(.{ .bg_color = 0xabcdef, .font_size = 20 });
    _ = row.spacer();
    _ = row.divider();
    const field = row.textField(core.Binding([]const u8){
        .context = undefined,
        .read = struct {
            fn read(_: *anyopaque) []const u8 {
                return "text";
            }
        }.read,
        .write = struct {
            fn write(_: *anyopaque, _: []const u8) !void {}
        }.write,
    }).placeholder("Enter text");
    try snapshot.finish();
    const options = label.parent.?.options;
    try std.testing.expectEqual(40, options.width.?);
    try std.testing.expectEqual(2, options.weight);
    try std.testing.expectEqual(3, options.padding);
    try std.testing.expectEqual(0x123456, options.color.?);
    try std.testing.expectEqual(0xabcdef, options.bg_color.?);
    try std.testing.expectEqual(20, options.font_size.?);
    try std.testing.expect(row.parent.?.options.inverse);
    try std.testing.expectEqual(4, row.parent.?.options.gap);
    try std.testing.expectEqual(core.node.default_gap, grid.parent.?.options.gap);
    try std.testing.expectEqualStrings("Enter text", field.parent.?.options.placeholder.?);
    try std.testing.expectEqual(4, row.parent.?.children.items.len);
}

test "container and modifier options are validated at the deferred boundary" {
    const cases = [_]*const fn (core.Builder) void{
        struct {
            fn run(ui: core.Builder) void {
                _ = ui.vbox(.{ .gap = -1 });
            }
        }.run,
        struct {
            fn run(ui: core.Builder) void {
                _ = ui.label("x").style(.{ .font_size = 0 });
            }
        }.run,
        struct {
            fn run(ui: core.Builder) void {
                _ = ui.spacer().click(undefined);
            }
        }.run,
        struct {
            fn run(ui: core.Builder) void {
                _ = ui.label("x").columns(2, .{});
            }
        }.run,
    };
    const expected = [_]anyerror{ error.InvalidLayout, error.InvalidStyle, error.InvalidModifier, error.InvalidModifier };
    for (cases, expected) |declare, err| {
        const snapshot = try Snapshot.create(std.testing.allocator);
        defer snapshot.destroy();
        declare(snapshot.builder());
        try std.testing.expectError(err, snapshot.finish());
    }
}

fn expectCells(expected: []const ?core.grid.Cell, actual: []const ?core.grid.Cell) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try std.testing.expectEqual(want, got);
}
fn placeGrid(grid: core.Builder, snapshot: *Snapshot) !core.grid.Placement {
    const node = grid.parent.?;
    var children: [8]*const core.Node = undefined;
    for (node.children.items, 0..) |child, index| children[index] = child;
    _ = snapshot;
    return core.grid.place(std.testing.allocator, node, children[0..node.children.items.len]);
}

test "grid placement follows PUI: manual cells, dense modes, spans and expansion" {
    const a = std.testing.allocator;
    const snapshot = try Snapshot.create(a);
    defer snapshot.destroy();
    const ui = snapshot.builder();

    const manual = ui.grid(.{});
    _ = manual.label("A").gridCell(.{ .row = 0, .column = 0, .rowspan = 2 });
    _ = manual.label("unplaced").gridCell(.{ .columnspan = 2 });
    _ = manual.label("B").gridCell(.{ .row = 1 }).gridCell(.{ .column = 2, .columnspan = 2 });
    const m = try placeGrid(manual, snapshot);
    defer a.free(m.cells);
    try expectCells(&.{ .{ .row = 0, .column = 0, .rowspan = 2 }, null, .{ .row = 1, .column = 2, .columnspan = 2 } }, m.cells);
    try std.testing.expectEqual(4, m.columns);
    try std.testing.expectEqual(2, m.rows);

    // A hole at (1,0) is left of the cursor: ordered placement revisits the
    // previous row, forward placement never goes back.
    const modes = [_]?bool{ null, false, true };
    const expected_e = [_]core.grid.Cell{ .{ .row = 1, .column = 0 }, .{ .row = 2, .column = 0 }, .{ .row = 1, .column = 0 } };
    for (modes, expected_e) |dense, e| {
        const auto = ui.grid(.{}).columns(4, .{ .dense = dense, .expand_children = false });
        _ = auto.label("A");
        _ = auto.label("B").gridCell(.{ .rowspan = 2 });
        _ = auto.label("C").gridCell(.{ .columnspan = 2 });
        _ = auto.label("D").gridCell(.{ .columnspan = 2 });
        _ = auto.label("E");
        _ = auto.label("hidden").visible(false);
        const p = try placeGrid(auto, snapshot);
        defer a.free(p.cells);
        try expectCells(&.{
            .{ .row = 0, .column = 0 },
            .{ .row = 0, .column = 1, .rowspan = 2 },
            .{ .row = 0, .column = 2, .columnspan = 2 },
            .{ .row = 1, .column = 2, .columnspan = 2 },
            e,
            null,
        }, p.cells);
    }

    // Dense placement backfills earlier rows.
    const backfill = ui.grid(.{}).columns(3, .{ .dense = true, .expand_children = false });
    _ = backfill.label("A").gridCell(.{ .columnspan = 2 });
    _ = backfill.label("B").gridCell(.{ .columnspan = 2 });
    _ = backfill.label("C");
    const d = try placeGrid(backfill, snapshot);
    defer a.free(d.cells);
    try std.testing.expectEqual(core.grid.Cell{ .row = 0, .column = 2 }, d.cells[2].?);

    // Expansion grows right into free columns and down to the bottom row;
    // oversized spans are clamped to the column count.
    const grow = ui.grid(.{}).columns(2, .{});
    _ = grow.label("A").gridCell(.{ .rowspan = 2 });
    _ = grow.label("B");
    _ = grow.label("C").gridCell(.{ .columnspan = 5 });
    const g = try placeGrid(grow, snapshot);
    defer a.free(g.cells);
    try expectCells(&.{
        .{ .row = 0, .column = 0, .rowspan = 2 },
        .{ .row = 0, .column = 1, .rowspan = 2 },
        .{ .row = 2, .column = 0, .columnspan = 2 },
    }, g.cells);

    try std.testing.expect(snapshot.build.failure == null);
    _ = ui.label("x").gridCell(.{ .rowspan = 0 });
    try std.testing.expectEqual(error.InvalidLayout, snapshot.build.failure.?);
}

// Reconciliation, checked against the native-free backend like CPPUI's
// tests/core_reconciliation.cpp: every physical node's records must equal its
// flattened declarations, in order.

fn collectPhysical(node: *core.Node, out: *std.ArrayListUnmanaged(*core.Node)) !void {
    for (node.children.items) |child| {
        if (child.is_virtual) try collectPhysical(child, out) else try out.append(std.testing.allocator, child);
    }
}
fn expectMountedOrder(node: *core.Node) !void {
    if (!node.is_virtual) {
        var physical = std.ArrayListUnmanaged(*core.Node).empty;
        defer physical.deinit(std.testing.allocator);
        try collectPhysical(node, &physical);
        const record = Backend.native(node).?;
        try std.testing.expectEqual(physical.items.len, record.len);
        for (physical.items, record.items()) |child, native| try std.testing.expectEqual(Backend.native(child).?, native);
    }
    for (node.children.items) |child| try expectMountedOrder(child);
}
fn serial(root: *core.Root, id: []const u8) usize {
    return root.find(id).?.serial;
}

const Items = struct {
    keys: []const []const u8 = &.{ "a", "b", "c" },
    kinds: []const core.node.Kind = &.{},
    nested: ?*Items = null,
    nested_at: usize = 0,
    grid: bool = false,
    calls: usize = 0,
    pub fn content(self: *@This(), ui: *core.Builder) void {
        self.calls += 1;
        const box = if (self.grid) ui.grid(.{}).id("box") else ui.vbox(.{}).id("box");
        for (self.keys, 0..) |key, index| {
            if (self.nested) |nested| if (index == self.nested_at) {
                _ = box.subView(nested).id("nested");
            };
            if (self.grid) {
                const cell: core.GridCell = if (key[0] == '_') .{} else .{ .row = @intCast(index % 2), .column = @intCast(index / 2) };
                _ = box.label(key).id(key).gridCell(cell);
            } else _ = box.label(key).id(key);
        }
        for (self.kinds) |kind| _ = switch (kind) {
            .button => box.button("b"),
            .spacer => box.spacer(),
            else => box.label("l"),
        };
    }
};

test "keyed moves reuse natives and keep mounted order" {
    var model = Items{};
    var root: core.Root = undefined;
    try root.init(std.testing.allocator, &model);
    defer root.deinit();
    try root.flush();
    const a = serial(&root, "a");
    const c = serial(&root, "c");
    const created = Backend.created;
    for ([_][]const []const u8{
        &.{ "c", "b", "a" },
        &.{ "b", "c", "a", "d" },
        &.{ "a", "d" },
        &.{ "d", "e", "a", "c" },
    }) |keys| {
        model.keys = keys;
        root.invalidate();
        try root.flush();
        try expectMountedOrder(root.container);
    }
    try std.testing.expectEqual(a, serial(&root, "a"));
    try std.testing.expect(serial(&root, "c") != c); // "c" was removed in between
    // One record per new key: d, e and the re-added c.
    try std.testing.expectEqual(created + 3, Backend.created);
}

test "unkeyed siblings match by type in sequence, as in CPPUI" {
    var model = Items{ .keys = &.{}, .kinds = &.{ .label, .button, .label } };
    var root: core.Root = undefined;
    try root.init(std.testing.allocator, &model);
    defer root.deinit();
    try root.flush();
    const box = Backend.native(root.view.node.children.items[0]).?;
    const button = box.items()[1];
    const second_label = box.items()[2];
    const created = Backend.created;
    // Removing the first label keeps the button and a label (step 3-2-1 requeues
    // the first label, so the second one is retained); index matching would
    // have remounted both.
    model.kinds = &.{ .button, .label };
    root.invalidate();
    try root.flush();
    try expectMountedOrder(root.container);
    try std.testing.expectEqual(created, Backend.created);
    try std.testing.expectEqual(button, box.items()[0]);
    try std.testing.expectEqual(second_label, box.items()[1]);
    // Spacers are not movable: a blocked spacer is recreated, not moved.
    model.kinds = &.{ .spacer, .button };
    root.invalidate();
    try root.flush();
    try expectMountedOrder(root.container);
    try std.testing.expectEqual(button, box.items()[1]);
}

test "Views flatten into their physical parent and redraw at their offset" {
    var inner = Items{ .keys = &.{ "x", "y" } };
    var model = Items{ .nested = &inner, .nested_at = 1 };
    var root: core.Root = undefined;
    try root.init(std.testing.allocator, &model);
    defer root.deinit();
    try root.flush();
    try expectMountedOrder(root.container);
    // A View contributes no native of its own: its box mounts into the outer box.
    const outer = Backend.native(root.view.node.children.items[0]).?;
    try std.testing.expectEqual(4, outer.len);
    inner.keys = &.{ "y", "z", "x" };
    root.findView("nested").?.invalidate();
    try root.flush();
    try std.testing.expectEqual(1, model.calls);
    try expectMountedOrder(root.container);
    // Moving the View moves its whole subtree.
    model.nested_at = 0;
    model.keys = &.{ "c", "a", "b" };
    root.invalidate();
    try root.flush();
    try std.testing.expectEqual(2, inner.calls);
    try expectMountedOrder(root.container);
    try std.testing.expectEqual(0, root.findView("nested").?.observer.dependencies.items.len);
}

test "manual grids never mount unplaced children and mount the rest in cell order" {
    var model = Items{ .keys = &.{ "a", "_unplaced", "b", "c" }, .grid = true };
    var root: core.Root = undefined;
    try root.init(std.testing.allocator, &model);
    defer root.deinit();
    try root.flush();
    try std.testing.expect(root.find("_unplaced") == null);
    try expectMountedOrder(root.container);
    // (row, column): a=(0,0), b=(0,1), c=(1,1) mount in that order.
    const grid = root.view.node.children.items[0];
    const ids = [_][]const u8{ "a", "b", "c" };
    for (grid.children.items, ids) |child, id| try std.testing.expectEqualStrings(id, child.options.id.?);
}

test "a failed native creation keeps the mounted tree consistent and retries" {
    var model = Items{};
    var root: core.Root = undefined;
    try root.init(std.testing.allocator, &model);
    defer root.deinit();
    try root.flush();
    model.keys = &.{ "a", "new", "c" };
    root.invalidate();
    Backend.fail_create = true;
    try std.testing.expectError(error.NativeCreateFailed, root.flush());
    Backend.fail_create = false;
    try expectMountedOrder(root.container);
    try std.testing.expect(root.view.observer.dirty);
    try root.flush();
    try expectMountedOrder(root.container);
    try std.testing.expect(root.find("new") != null and root.find("b") == null);
}

fn syncAllocationScenario(allocator: Allocator) !void {
    var inner = Items{ .keys = &.{ "x", "y" } };
    var model = Items{ .nested = &inner, .nested_at = 1, .kinds = &.{ .label, .button } };
    var root: core.Root = undefined;
    try root.init(allocator, &model);
    defer root.deinit();
    root.flush() catch |err| {
        try root.flush();
        try expectMountedOrder(root.container);
        return err;
    };
    model.keys = &.{ "c", "d", "a" };
    model.nested_at = 2;
    model.kinds = &.{ .button, .label, .label };
    inner.keys = &.{ "y", "z" };
    root.invalidate();
    root.findView("nested").?.invalidate();
    root.flush() catch |err| {
        try expectMountedOrder(root.container);
        try root.flush();
        try expectMountedOrder(root.container);
        try std.testing.expect(root.find("z") != null and root.find("b") == null);
        return err;
    };
}

test "every allocation failure during sync leaves a consistent, retryable tree" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, syncAllocationScenario, .{});
    try std.testing.expectEqual(0, Backend.live);
}
