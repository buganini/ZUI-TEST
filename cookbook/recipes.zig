const zui = @import("zui");
const Model = @import("model.zig").Model;

pub const Recipe = struct {
    key: [:0]const u8,
    title: [:0]const u8,
    content: ?*const fn (*Model, *zui.Builder) anyerror!void = null,
    remaining: [:0]const u8 = "",

    pub fn status(self: Recipe) [:0]const u8 {
        return if (self.content == null) "not ported" else if (self.remaining.len > 0) "partial" else "ported";
    }
};

// Keep CPPUI's cookbook keys and ordering so missing capabilities stay visible.
pub const all = [_]Recipe{
    .{ .key = "adaptive", .title = "Adaptive", .remaining = "Responsive layout" },
    .{ .key = "vbox", .title = "VBox", .content = @import("vbox.zig").content },
    .{ .key = "hbox", .title = "HBox", .content = @import("hbox.zig").content },
    .{ .key = "stack", .title = "Stack", .remaining = "Stack layout" },
    .{ .key = "grid", .title = "Grid", .content = @import("grid.zig").content, .remaining = "Explicit coordinates and spans" },
    .{ .key = "adaptive_grid", .title = "Adaptive Grid", .remaining = "Responsive grid" },
    .{ .key = "label", .title = "Label", .content = @import("label.zig").content },
    .{ .key = "text", .title = "Text", .remaining = "Rich text, HTML and Markdown" },
    .{ .key = "button", .title = "Button", .content = @import("button.zig").content },
    .{ .key = "checkbox", .title = "Checkbox", .content = @import("checkbox.zig").content, .remaining = "Collection membership bindings" },
    .{ .key = "radiobutton", .title = "RadioButton", .remaining = "Value selection" },
    .{ .key = "combobox", .title = "Combobox", .remaining = "Selection binding" },
    .{ .key = "progressbar", .title = "ProgressBar", .remaining = "Progress display" },
    .{ .key = "timeline", .title = "TimelineView", .remaining = "Cancellable timers" },
    .{ .key = "maskedfield", .title = "MaskedField", .remaining = "Password editor" },
    .{ .key = "textedit", .title = "TextEdit", .remaining = "Multiline editor" },
    .{ .key = "textfield", .title = "TextField", .content = @import("textfield.zig").content, .remaining = "Editing buffer and numeric conversion" },
    .{ .key = "scroll", .title = "Scroll", .content = @import("scroll.zig").content, .remaining = "Scroll offsets and end anchoring" },
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
    .{ .key = "binding", .title = "State Binding", .content = @import("binding.zig").content, .remaining = "Radio and combobox binding examples" },
    .{ .key = "widget", .title = "WidgetWrapper", .remaining = "Borrowed native widget ownership" },
    .{ .key = "drop", .title = "Drop", .remaining = "Drag and drop events" },
    .{ .key = "mdi", .title = "MDI", .remaining = "Multiple document windows" },
    .{ .key = "splitter", .title = "Splitter", .content = @import("splitter.zig").content, .remaining = "More than two panes per splitter" },
    .{ .key = "modal", .title = "Modal", .remaining = "Modal visibility binding" },
    .{ .key = "imperative", .title = "Imperative", .remaining = "Dialogs and typed results" },
};
