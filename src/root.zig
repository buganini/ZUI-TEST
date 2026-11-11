pub const native = @import("c");
const core = @import("core");
pub const node = core.node;
pub const view = core.view;
pub const dom = core.dom;
pub const state = core.state;
pub const lvgl = @import("lvgl");
pub const Node = core.Node;
pub const View = core.View;
pub const Root = core.Root;
pub const Application = lvgl.Application;
pub const ApplicationOptions = lvgl.ApplicationOptions;
pub const Builder = core.Builder;
pub const Layout = core.Layout;
pub const Style = core.Style;
pub const GridCell = core.GridCell;
pub const State = core.State;
pub const TextState = core.TextState;
pub const Binding = core.Binding;
pub const Signal = core.Signal;
pub const callback = core.callback;

test {
    _ = @import("integration_tests.zig");
    _ = @import("view_tests.zig");
}
