pub const native = @import("c");
const core = @import("core");
pub const node = core.node;
pub const view = core.view;
pub const dom = core.dom;
pub const state = core.state;
pub const lvgl = @import("lvgl/backend.zig");
pub const Node = core.Node;
pub const View = core.View;
/// The DOM specialized for the LVGL backend.
pub const Dom = core.dom.Dom(lvgl.Backend);
pub const Application = @import("lvgl/application.zig").Application;
pub const ApplicationOptions = @import("lvgl/application.zig").ApplicationOptions;
pub const Builder = core.Builder;
pub const Layout = core.Layout;
pub const Style = core.Style;
pub const State = core.State;
pub const TextState = core.TextState;
pub const Binding = core.Binding;
pub const Signal = core.Signal;
pub const callback = core.callback;

test {
    _ = @import("integration_tests.zig");
    _ = @import("view_tests.zig");
}
