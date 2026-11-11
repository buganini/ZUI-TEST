pub const native = @import("c");
const core = @import("core");
pub const node = core.node;
pub const view = core.view;
pub const dom = @import("dom.zig");
pub const state = core.state;
pub const Node = core.Node;
pub const View = core.View;
pub const Dom = dom.Dom;
pub const App = @import("app.zig").App;
pub const AppOptions = @import("app.zig").AppOptions;
pub const Builder = core.Builder;
pub const State = core.State;
pub const TextState = core.TextState;
pub const Binding = core.Binding;
pub const Signal = core.Signal;
pub const Options = core.Options;
pub const callback = core.callback;

test {
    _ = @import("integration_tests.zig");
}
