const zui = @import("zui");
const Model = @import("model.zig").Model;

pub const Recipe = struct {
    key: [:0]const u8,
    title: [:0]const u8,
    render: ?*const fn (*Model, *zui.Builder) anyerror!void = null,
    remaining: [:0]const u8 = "",

    pub fn status(self: Recipe) [:0]const u8 {
        return if (self.render == null) "not ported" else if (self.remaining.len > 0) "partial" else "ported";
    }
};

// Keep CPPUI's cookbook keys and ordering so missing capabilities stay visible.
pub const all = [_]Recipe{
    .{ .key = "adaptive", .title = "Adaptive", .remaining = "Responsive layout" },
    .{ .key = "vbox", .title = "VBox", .render = @import("vbox.zig").render },
    .{ .key = "hbox", .title = "HBox", .render = @import("hbox.zig").render },
    .{ .key = "stack", .title = "Stack", .remaining = "Stack layout" },
    .{ .key = "grid", .title = "Grid", .render = @import("grid.zig").render, .remaining = "Explicit coordinates and spans" },
    .{ .key = "adaptive_grid", .title = "Adaptive Grid", .remaining = "Responsive grid" },
    .{ .key = "label", .title = "Label", .render = @import("label.zig").render },
    .{ .key = "text", .title = "Text", .remaining = "Rich text, HTML and Markdown" },
    .{ .key = "button", .title = "Button", .render = @import("button.zig").render },
    .{ .key = "checkbox", .title = "Checkbox", .render = @import("checkbox.zig").render, .remaining = "Collection membership bindings" },
    .{ .key = "radiobutton", .title = "RadioButton", .remaining = "Value selection" },
    .{ .key = "combobox", .title = "Combobox", .remaining = "Selection binding" },
    .{ .key = "progressbar", .title = "ProgressBar", .remaining = "Progress display" },
    .{ .key = "timeline", .title = "TimelineView", .remaining = "Cancellable timers" },
    .{ .key = "maskedfield", .title = "MaskedField", .remaining = "Password editor" },
    .{ .key = "textedit", .title = "TextEdit", .remaining = "Multiline editor" },
    .{ .key = "textfield", .title = "TextField", .render = @import("textfield.zig").render, .remaining = "Editing buffer and numeric conversion" },
    .{ .key = "scroll", .title = "Scroll", .render = @import("scroll.zig").render, .remaining = "Scroll offsets and end anchoring" },
    .{ .key = "heavycanvas", .title = "HeavyCanvas", .remaining = "Large canvas rendering" },
    .{ .key = "canvas", .title = "Canvas", .remaining = "Painter and input APIs" },
    .{ .key = "image", .title = "Image", .remaining = "Image resources" },
    .{ .key = "tab", .title = "Tab", .remaining = "Tabs and selection" },
    .{ .key = "views", .title = "Views", .remaining = "Retained inactive pages" },
    .{ .key = "refs", .title = "Refs", .remaining = "Typed references" },
    .{ .key = "table", .title = "Table", .remaining = "Table data and identity" },
    .{ .key = "table_adapter", .title = "Table (Adapter)", .remaining = "Table adapter" },
    .{ .key = "tree", .title = "Tree", .remaining = "Tree data and identity" },
    .{ .key = "tree_adapter", .title = "Tree (Adapter)", .remaining = "Tree adapter" },
    .{ .key = "binding", .title = "State Binding", .render = @import("binding.zig").render, .remaining = "Radio and combobox binding examples" },
    .{ .key = "widget", .title = "WidgetWrapper", .remaining = "Borrowed native widget ownership" },
    .{ .key = "drop", .title = "Drop", .remaining = "Drag and drop events" },
    .{ .key = "mdi", .title = "MDI", .remaining = "Multiple document windows" },
    .{ .key = "splitter", .title = "Splitter", .render = @import("splitter.zig").render, .remaining = "More than two panes per splitter" },
    .{ .key = "modal", .title = "Modal", .remaining = "Modal visibility binding" },
    .{ .key = "imperative", .title = "Imperative", .remaining = "Dialogs and typed results" },
};
