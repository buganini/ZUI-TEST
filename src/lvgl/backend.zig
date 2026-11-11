//! The LVGL backend, like cppui/lvgl/backend.hpp: one file per widget, plus
//! the hooks that core's Node and dom.sync() call.
const c = @import("c");
const core = @import("core");
const Node = core.Node;
const base = @import("base.zig");

pub const Widget = base.Widget;
pub const Native = *c.lv_obj_t;
pub const Application = @import("application.zig").Application;
pub const ApplicationOptions = @import("application.zig").ApplicationOptions;

pub fn native(node: *const Node) ?Native {
    return node.ui.object;
}

pub fn update(node: *Node, prev: ?*Node) !void {
    base.adopt(node, prev);
    switch (node.kind) {
        .root, .column, .row => try @import("layout.zig").update(node),
        .grid => try @import("grid.zig").update(node),
        .scroll => try @import("scroll.zig").update(node),
        .splitter => try @import("splitter.zig").update(node),
        .spacer => try @import("spacer.zig").update(node),
        .divider => try @import("divider.zig").update(node),
        .label => try @import("label.zig").update(node),
        .button => try @import("button.zig").update(node),
        .checkbox => try @import("checkbox.zig").update(node),
        .text_field => try @import("textfield.zig").update(node),
        .view => unreachable,
    }
    base.applyOptions(node);
}
pub fn postUpdate(_: *Node) void {}
pub fn postSync(node: *Node) !void {
    switch (node.kind) {
        .grid => try @import("grid.zig").postSync(node),
        .splitter => try @import("splitter.zig").postSync(node),
        else => {},
    }
}
pub const addChild = base.addChild;
pub const removeChild = base.removeChild;
pub const destroy = base.destroy;
pub const release = base.release;
