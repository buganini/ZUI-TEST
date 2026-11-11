//! A native-free backend for core tests, like the TestNode in CPPUI's
//! tests/core_reconciliation.cpp. Records keep the mounted order so tests can
//! check that sync() moves natives exactly as it moves declarations.
const std = @import("std");
const core = @import("core");
const Node = core.Node;

pub const Record = struct {
    allocator: std.mem.Allocator,
    serial: usize,
    kind: core.node.Kind,
    children: [64]*Record = undefined,
    len: usize = 0,

    pub fn items(self: *Record) []*Record {
        return self.children[0..self.len];
    }
    fn indexOf(self: *Record, child: *Record) ?usize {
        return std.mem.indexOfScalar(*Record, self.items(), child);
    }
};
pub const Native = *Record;
pub const Widget = struct {
    object: ?*Record = null,
};

pub var live: usize = 0;
pub var serial: usize = 0;
/// Counts update(prev) calls that created a record, to check retention.
pub var created: usize = 0;
/// Set to make the next creation fail, like an LVGL create returning null.
pub var fail_create: bool = false;

pub fn native(node: *const Node) ?Native {
    return node.ui.object;
}

pub fn update(node: *Node, prev: ?*Node) !void {
    if (prev) |previous| {
        node.ui = previous.ui;
        previous.ui = .{};
    }
    if (node.ui.object == null) {
        if (fail_create) return error.NativeCreateFailed;
        const record = try node.allocator.create(Record);
        serial += 1;
        record.* = .{ .allocator = node.allocator, .serial = serial, .kind = node.kind };
        node.ui.object = record;
        live += 1;
        created += 1;
    }
}
pub fn postUpdate(_: *Node) void {}
pub fn postSync(_: *Node) !void {}

pub fn addChild(parent: *Node, index: usize, child: *Node) void {
    const record = parent.ui.object.?;
    const native_child = child.ui.object.?;
    std.debug.assert(record.indexOf(native_child) == null);
    std.debug.assert(index <= record.len);
    std.mem.copyBackwards(*Record, record.children[index + 1 .. record.len + 1], record.children[index..record.len]);
    record.children[index] = native_child;
    record.len += 1;
}
pub fn removeChild(parent: *Node, index: usize, child: *Node) void {
    const record = parent.ui.object.?;
    // Declaration order must equal mounted native order.
    std.debug.assert(index < record.len and record.children[index] == child.ui.object.?);
    std.mem.copyForwards(*Record, record.children[index .. record.len - 1], record.children[index + 1 .. record.len]);
    record.len -= 1;
}
pub fn destroy(node: *Node, _: bool) void {
    if (node.ui.object) |record| {
        record.allocator.destroy(record);
        live -= 1;
    }
    node.ui = .{};
}
pub fn release(node: *Node) void {
    std.debug.assert(node.ui.object == null);
}
