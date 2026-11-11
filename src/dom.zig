const std = @import("std");
const Node = @import("node.zig").Node;
const List = Node.List;

// A port of CPPUI's dom.hpp (and PUI's dom.py): keyed reconciliation of a
// container's new declarations against its mounted ones, in one pass that
// adds, removes and moves native children at flattened offsets.
//
// Zig has no exceptions. When update() or a nested sync fails part way, sync()
// leaves `new` holding exactly the mounted nodes, in native order, and frees
// everything else, so the caller's tree stays consistent and the next redraw
// can retry.

pub const Result = struct {
    num: isize = 0,
    delta: isize = 0,
};

fn indexOfSince(nodes: []const *Node, since: usize, node: *const Node) ?usize {
    var i = since;
    while (i < nodes.len) : (i += 1) {
        if (nodes[i].eql(node)) return i;
    }
    return null;
}

/// Destroy a subtree. Virtual nodes have no native owner to delete their
/// descendants, so direct ownership passes through them to physical nodes.
pub fn recurDelete(child: *Node, direct: bool) void {
    child.destroyed = true;
    for (child.children.items) |sub| recurDelete(sub, direct and child.is_virtual);
    child.children.clearRetainingCapacity();
    child.destroy(direct);
    child.free();
}

/// Free a declaration whose native state its successor adopted. Its children
/// were reconciled separately and are not freed here.
fn releaseRetired(node: *Node) void {
    node.children.clearRetainingCapacity();
    node.free();
}

/// Unmount a node; returns how many ordered native children it held.
fn domRemoveNode(dom_parent: *Node, dom_offset: usize, child: *Node) isize {
    if (child.is_virtual) {
        var removed: isize = 0;
        for (child.children.items) |sub| removed += domRemoveNode(dom_parent, dom_offset, sub);
        return removed;
    }
    dom_parent.removeChild(dom_offset, child);
    return if (child.is_outoforder) 0 else 1;
}

fn domAddNodes(dom_parent: *Node, dom_offset: usize, child: *Node, index: *usize) void {
    if (child.is_virtual) {
        for (child.children.items) |sub| domAddNodes(dom_parent, dom_offset, sub, index);
        return;
    }
    dom_parent.addChild(dom_offset + index.*, child);
    if (!child.is_outoforder) index.* += 1;
}

pub fn countDomChildren(nodes: []const *Node) isize {
    var num: isize = 0;
    for (nodes) |child| {
        if (child.is_virtual) num += countDomChildren(child.children.items) else if (!child.is_outoforder) num += 1;
    }
    return num;
}

fn rebindDomParent(node: *Node, dom_parent: *Node) void {
    node.dom_parent = dom_parent;
    // A physical child owns the parent relationship for its own subtree.
    if (node.is_virtual) for (node.children.items) |child| rebindDomParent(child, dom_parent);
}

fn gridKey(node: *const Node) [4]i32 {
    const cell = node.options.grid;
    return .{
        if (cell.row) |v| v else -1,
        if (cell.column) |v| v else -1,
        if (cell.rowspan) |v| v else -1,
        if (cell.columnspan) |v| v else -1,
    };
}
fn gridLess(_: void, a: *Node, b: *Node) bool {
    const left = gridKey(a);
    const right = gridKey(b);
    return std.mem.order(i32, &left, &right) == .lt;
}

fn prepareDom(node: *Node, new: *List) void {
    if (node.is_grid_layout and node.options.columns == null) {
        // Unplaced declarations never mount.
        var kept: usize = 0;
        for (new.items) |child| {
            if (child.options.grid.row == null or child.options.grid.column == null) {
                recurDelete(child, true);
            } else {
                new.items[kept] = child;
                kept += 1;
            }
        }
        new.shrinkRetainingCapacity(kept);
        std.sort.insertion(*Node, new.items, {}, gridLess);
        return;
    }
    // Ordered children first, then out-of-order ones (popups), as in CPPUI.
    var ordered: usize = 0;
    for (new.items, 0..) |child, i| {
        if (child.is_outoforder) continue;
        std.mem.rotate(*Node, new.items[ordered .. i + 1], i - ordered);
        ordered += 1;
    }
    if (node.is_reversed_order) std.mem.reverse(*Node, new.items[0..ordered]);
}

/// Reconcile `node`'s mounted children `old` with its new declarations `new`.
/// Native children are mounted into `dom_parent` starting at `dom_offset`.
/// On return, `new` is the mounted list and `old` may be discarded.
pub fn sync(node: *Node, dom_parent: *Node, dom_offset: usize, old: *List, new: *List, depth: usize) anyerror!Result {
    const allocator = node.allocator;
    const orig_dom_children_num = countDomChildren(old.items);
    var dom_children_num = orig_dom_children_num;
    var dom_children_curr: isize = 0;

    prepareDom(node, new);

    var to_be_deleted = List.empty;
    defer to_be_deleted.deinit(allocator);
    var retired = List.empty;
    defer retired.deinit(allocator);
    // new[0..processed] and old[0..processed] are pairwise reconciled; old's
    // entry is either the same node or a retired predecessor.
    var processed: usize = 0;
    errdefer {
        for (new.items[processed..]) |child| recurDelete(child, true);
        @memcpy(old.items[0..processed], new.items[0..processed]);
        std.mem.swap(List, old, new);
        for (retired.items) |child| releaseRetired(child);
        for (to_be_deleted.items) |child| recurDelete(child, true);
    }
    try old.ensureUnusedCapacity(allocator, new.items.len);
    try to_be_deleted.ensureTotalCapacity(allocator, old.items.len);
    try retired.ensureTotalCapacity(allocator, old.items.len);

    const offset: isize = @intCast(dom_offset);
    var child_index: usize = 0;
    while (child_index < new.items.len) : (child_index += 1) {
        const new_node = new.items[child_index];
        new_node.dom_parent = dom_parent;

        while (true) {
            // Step 1: the current nodes match.
            if (child_index < old.items.len) {
                const old_node = old.items[child_index];
                if (old_node.eql(new_node)) {
                    if (old_node.is_view) {
                        // A retained View keeps its own children and subscriptions.
                        dom_children_curr += countDomChildren(old_node.children.items);
                        old_node.parent = new_node.parent;
                        rebindDomParent(old_node, dom_parent);
                        new.items[child_index] = old_node;
                        recurDelete(new_node, true);
                        processed = child_index + 1;
                    } else {
                        const was_mounted = Node.Backend.native(old_node) != null;
                        try new_node.update(old_node);
                        retired.appendAssumeCapacity(old_node);
                        processed = child_index + 1;
                        if (new_node.is_virtual) {
                            const result = try sync(new_node, dom_parent, @intCast(offset + dom_children_curr), &old_node.children, &new_node.children, depth + 1);
                            dom_children_curr += result.num;
                            dom_children_num += result.delta;
                        } else {
                            // A native deleted outside ZUI was recreated at the end.
                            if (!was_mounted) dom_parent.addChild(@intCast(offset + dom_children_curr), new_node);
                            if (!new_node.is_outoforder) dom_children_curr += 1;
                            if (!new_node.is_terminal)
                                _ = try sync(new_node, new_node, 0, &old_node.children, &new_node.children, depth + 1);
                        }
                    }
                    break;
                }
            }

            // Step 2: trim old nodes that do not occur in the remaining new DOM.
            var trimmed = false;
            while (child_index < old.items.len and indexOfSince(new.items, child_index, old.items[child_index]) == null) {
                const old_node = old.orderedRemove(child_index);
                dom_children_num -= domRemoveNode(dom_parent, @intCast(offset + dom_children_curr), old_node);
                to_be_deleted.appendAssumeCapacity(old_node);
                trimmed = true;
            }
            if (trimmed) continue;

            // Step 3: add the target or move an existing matching node.
            const matched = if (new_node.is_movable) indexOfSince(old.items, child_index + 1, new_node) else null;
            if (matched) |matched_index| {
                if (matched_index == child_index + 1 and old.items[child_index].is_movable) {
                    // Step 3-2-1: yield the next position by requeueing its blocker.
                    const blocker = old.orderedRemove(child_index);
                    const n = domRemoveNode(dom_parent, @intCast(offset + dom_children_curr), blocker);
                    var index: usize = 0;
                    domAddNodes(dom_parent, @intCast(offset + dom_children_num - n), blocker, &index);
                    old.appendAssumeCapacity(blocker);
                } else {
                    // Step 3-2-2: move the target into the current position.
                    const old_node = old.items[matched_index];
                    const source = offset + countDomChildren(old.items[0..matched_index]);
                    _ = old.orderedRemove(matched_index);
                    _ = domRemoveNode(dom_parent, @intCast(source), old_node);
                    var index: usize = 0;
                    domAddNodes(dom_parent, @intCast(offset + dom_children_curr), old_node, &index);
                    old.insertAssumeCapacity(child_index, old_node);
                }
                continue; // Step 1 reconciles the moved node.
            }

            // Step 3-1: new node.
            try new_node.update(null);
            old.insertAssumeCapacity(child_index, new_node);
            processed = child_index + 1;
            if (new_node.is_virtual) {
                var empty = List.empty;
                defer empty.deinit(allocator);
                const result = try sync(new_node, dom_parent, @intCast(offset + dom_children_curr), &empty, &new_node.children, depth + 1);
                dom_children_curr += result.num;
                dom_children_num += result.num;
            } else {
                dom_parent.addChild(@intCast(offset + dom_children_curr), new_node);
                if (!new_node.is_outoforder) {
                    dom_children_curr += 1;
                    dom_children_num += 1;
                }
                if (!new_node.is_terminal) {
                    var empty = List.empty;
                    defer empty.deinit(allocator);
                    _ = try sync(new_node, new_node, 0, &empty, &new_node.children, depth + 1);
                }
            }
            break;
        }
    }

    // Step 4: trim the old trail.
    while (old.items.len > new.items.len) {
        const old_node = old.orderedRemove(new.items.len);
        dom_children_num -= domRemoveNode(dom_parent, @intCast(offset + dom_children_curr), old_node);
        to_be_deleted.appendAssumeCapacity(old_node);
    }

    for (new.items) |child| child.postUpdate();
    try node.postSync();
    if (node.is_virtual and dom_parent != node) try dom_parent.postSync();

    // Every new node is mounted; nothing below may fail.
    processed = new.items.len;
    @memcpy(old.items[0..processed], new.items);
    for (to_be_deleted.items) |child| recurDelete(child, true);
    to_be_deleted.clearRetainingCapacity();
    for (retired.items) |child| releaseRetired(child);
    retired.clearRetainingCapacity();

    if (dom_children_curr != dom_children_num) return error.DomChildCountMismatch;
    return .{ .num = dom_children_curr, .delta = dom_children_num - orig_dom_children_num };
}
