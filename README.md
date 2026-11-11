# ZUI

ZUI is a declarative UI framework in Zig, developed after
[PUI (Python)](https://github.com/buganini/PUI) and
[CPPUI (C++)](https://github.com/buganini/CPPUI).
It currently targets **LVGL**, with an SDL2 desktop host on Linux.

The first working version includes reactive state and two-way bindings,
independent retained SubViews, id-based widget reuse, HBox/VBox, Grid, Scroll, Splitter,
Spacer, Divider, Label, Button, Checkbox and TextField. Names and argument shapes
follow PUI and CPPUI; see [Differences from PUI / CPPUI](#differences-from-pui--cppui).
The [cookbook](cookbook/README.md) follows
[CPPUI's cookbook](https://github.com/buganini/CPPUI/tree/main/cookbook): a
scrollable example list, draggable Code / Result panes and runtime source reload.
Eleven interactive recipes are available; the remaining pages show their missing
capabilities. A smaller demo combines a counter, a form and keyed editors.

## Build and run

Requirements:

- Zig **0.17.1** (the minimum version and the version in `.zigversion`).
- LVGL **9.6.0** source; the adapter checks for the 9.6 API series.
- C/C++ toolchain, CMake 3.24+, SDL2 development files and pkg-config.
- Valgrind and LLVM-enabled Zig binaries for the optional memory checks.

On Ubuntu, native build dependencies are provided by `build-essential`, `cmake`,
`pkg-config` and `libsdl2-dev`. The build uses `zig` from `PATH` and does not
install a compiler or download dependencies automatically.

For a standalone checkout:

```sh
mkdir -p deps
git clone --branch v9.6.0 --depth 1 https://github.com/lvgl/lvgl.git deps/lvgl
zig build
zig build run
```

To reuse the neighboring CPPUI checkout:

```sh
zig build -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0
```

The main executable is `zig-out/bin/zui-cookbook` (1024 × 768). A graphical session is needed for
interactive use. Closing its window unwinds the application, removes callbacks
and frees the widget tree before shutting down LVGL and SDL.

```sh
# List recipe status without opening a window:
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0 -- --list
# Open a specific recipe:
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0 -- --recipe binding
# Keep the smaller example available:
zig build run-demo -Dlvgl-dir=../CPPUI/lvgl-9.6.0
```

The cookbook reads `.zig` source files from the absolute directory recorded at
build time, so it works from another working directory. **Reload** refreshes the
displayed source; rebuild to change the running recipe. Override the source
location with `-Dcookbook-source-dir=/path/to/cookbook` when packaging it.
Zig 0.14 support has been dropped; new code uses Zig 0.17's `std.Io` APIs.

The native build currently uses the host C/C++ toolchain. Cross compilation and
embedded display/input drivers are not implemented yet.

## Verify

```sh
# No LVGL, SDL2 or display required:
zig build test-core

# Use the same -Dlvgl-dir option for each command when reusing CPPUI:
zig build test -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build memcheck -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build snapshot -Dlvgl-dir=../CPPUI/lvgl-9.6.0
```

`test` covers state subscriptions, coalesced updates, builder failures,
checkbox/text bindings, caret retention, keyed reordering/removal, native
subtree deletion, isolated View updates, visibility retention, deferred SDL quit, splitter pointer/keyboard resizing, cookbook navigation,
source reload and the complete demo. Allocation-failure
checks exercise every Zig allocation on representative build/update paths.
Zig's testing allocator checks for leaked Zig allocations.

`memcheck` runs the LVGL, demo and cookbook tests under Valgrind. Invalid accesses and
**definite, indirect or possible** leaks fail the command; no project
suppressions are applied. These tests use Zig's LLVM backend so Valgrind can
read their debug information.

GUI tests and `snapshot` use SDL's dummy/software driver and need no display.
`snapshot` writes `.build/cookbook-<key>.bmp` for each implemented recipe and one
unported page, plus `.build/demo.bmp`. Physical input,
platform IME composition, accessibility and HiDPI behavior still need testing
in a real desktop session.

## API

An application model supplies `pub fn content(self, ui: *zui.Builder) void`.
Cookbook recipes also use `content()` as their UI declaration entry point,
following PUI / CPPUI:

```zig
pub fn content(self: *Counter, ui: *zui.Builder) void {
    const column = ui.vbox(.{ .gap = 8 }).layout(.{ .padding = 12 });
    _ = column.labelFmt("Count: {d}", .{self.count.get(ui)}).style(.{ .font_size = 20 });
    _ = column.button("+").id("increment").click(zui.callback(self, increment));
}

fn increment(self: *Counter) !void {
    try self.count.set(self.count.peek() + 1);
}
```

Every widget, container and SubView declaration returns a `Builder` handle.
Modifiers return the same handle for chaining; use `_ =` when its result is not
needed, or keep a `const` handle to add children to a container. Copies refer to
the same declaration node, so configuring a copy updates that declaration too.
Methods use Zig's `lowerCamelCase`; type names remain `TitleCase`.

The API mirrors PUI and CPPUI. Zig has no keyword arguments, so options that
PUI passes by keyword are anonymous structs, and only the fields you give are set:

| PUI / CPPUI | ZUI |
| --- | --- |
| `HBox(inverse=, gap=10)` / `VBox(...)` | `ui.hbox(.{ .inverse = true, .gap = 12 })` / `ui.vbox(.{})` |
| `Grid(gap=10)` | `ui.grid(.{ .gap = 10 })` (manual placement) |
| `.columns(n, dense=, expandChildren=)` | `.columns(n, .{ .dense = true, .expand_children = false })` |
| `.grid(row=, column=, rowspan=, columnspan=)` | `.gridCell(.{ .row = 0, .column = 1, .columnspan = 2 })` |
| `Scroll(vertical=None, horizontal=False)` | `ui.scroll(.{ .vertical = null, .horizontal = false })` |
| `Splitter(vertical=)` | `ui.splitter(.{ .vertical = true })`, optional `.ratio(binding)` |
| `SubView<T>()` / nested `PUIView` | `ui.subView(&model)` |
| `Spacer()`, `Divider()` | `ui.spacer()`, `ui.divider()` |
| `Label(text)`, `Button(text)` | `ui.label(text)`, `ui.labelFmt(fmt, args)`, `ui.button(text)` |
| `Checkbox(text, model)` | `ui.checkbox(text, binding)` |
| `TextField(model)` + `.placeholder()` | `ui.textField(binding).placeholder(text)` |
| `.id(name)` | `.id(name)` |
| `.click(callback)` | `.click(zui.callback(self, function))` on buttons and labels |
| `.layout(width=, height=, weight=, padding=)` | `.layout(.{ .width = 200, .weight = 1, .padding = 8 })` |
| `.style(color=, bgColor=, fontSize=)` | `.style(.{ .color = 0x336699, .bg_color = 0xfff7e6, .font_size = 20 })` |
| `.visible(value)`, `disabled=True` | `.visible(value)`, `.disabled(true)` |

Struct fields use Zig's `snake_case` (`bg_color`, `font_size`). The default gap
is 10 pixels, as in PUI and CPPUI.

Valid repeated settings use the last value. Invalid settings latch the first
error even if a later setter would correct them. Ids are copied and checked
against siblings on every `.id()` call. Leaf controls cannot contain children;
virtual SubViews accept `.id()` and take layout/visibility from their physical
containers. Invalid modifiers are reported at the same deferred error boundary.

Widget declarations and tracked reads do not need `try`. All builders in one
`content()` call share its first declaration error, including allocation failures
while formatting text or tracking dependencies. After a failure, subsequent UI
declarations do nothing, and failed containers remain safe to use. State and
explicit Binding reads still return real values so conditions and loops can
finish normally. Custom binding getters must be free of side effects.

Application checks the error after `content()` returns, before changing subscriptions or
native widgets. A failed render preserves the previous UI and subscriptions;
`flush()` / `pump()` returns the error. The next attempt starts with a fresh
error record. Ordinary Zig code in `content()` still executes after a declaration
failure, so keep application side effects in event callbacks.

Use `ui.fail(err)` to report a custom declaration error. Models may also return
`!void` for their own fallible operations; Application captures that error at the same
boundary, preserving any earlier Builder error. Model initialization, State
writes in callbacks, and Application operations remain explicitly fallible.

Create state with `zui.State(i32).init(allocator, 0)` and call `deinit()` after
its Application is destroyed. Editable text uses `try zui.TextState.init(allocator, text)`.
Both provide `.binding()` for controls. See [the complete demo](examples/main.zig)
for model setup, teardown and all supported widgets.

```zig
const app = try zui.Application.create(allocator, &model, .{ .title = "My application" });
defer app.destroy();
try app.run();
```

## Architecture

The modules mirror CPPUI (`node_header.hpp`/`node.hpp`, `view.hpp`, `dom.hpp`,
`cppui/lvgl/*.hpp`) and PUI (`node.py`, `view.py`, `dom.py`, one package per backend):

| Module | CPPUI | Responsibility |
| --- | --- | --- |
| [`node.zig`](src/node.zig) | `node_header.hpp`, `node.hpp` | `Node`: one declaration per render with CPPUI's flags (`is_virtual`, `is_terminal`, `is_movable`, …), identity (`eql`), DOM offsets and the hooks `sync()` calls; the `Builder` |
| [`view.zig`](src/view.zig) | `view.hpp`, `Application` | `View`: `content()`, subscriptions, `update()` and `redraw()`; `Root`: the root View, flush and native-callback guards |
| [`dom.zig`](src/dom.zig) | `dom.hpp` | `sync()`: keyed reconciliation with CPPUI's steps (match, trim, add, move/yield, trim tail), `recurDelete()` |
| [`grid.zig`](src/grid.zig) | `grid.hpp` | Backend-independent Grid placement |
| [`state.zig`](src/state.zig) | `state.hpp` | State, bindings, signals and observers |
| [`lvgl/`](src/lvgl/backend.zig) | `cppui/lvgl/` | One file per widget (`label.zig`, `layout.zig`, `grid.zig`, `splitter.zig`, …), shared `base.zig` and `application.zig` |

Like `cppui/backend.hpp`, core reaches widgets through a backend chosen at
build time: the `core` module imports `backend`, which is `src/lvgl/backend.zig`
for the library and the native-free `src/testing/backend.zig` for `test-core`.
Each render builds new `Node`s; `sync()` matches them against the mounted ones,
and a matched node takes over its predecessor's native state in `update(prev)`.
Only structural changes add, remove or move native children.

`root.zig` exposes these modules as `zui.node`, `zui.view`, `zui.dom`,
`zui.state` and `zui.lvgl`, as well as the usual top-level types.

```zig
pub fn content(self: *Window, ui: *zui.Builder) void {
    const page = ui.vbox(.{}).visible(self.show_counter.get(ui));
    _ = page.subView(&self.counter).id("counter");
}
```

All widgets and physical containers provide `.visible(bool)` (default `true`).
`.visible(false)` hides a retained control and excludes it from layout;
showing it again preserves its identity and unchanged editor caret. An `if`
around the declaration instead removes and later remounts it. Virtual SubViews
have no native visibility flag: put visibility on their physical container,
as above. Hidden Views currently keep processing reactive updates; CPPUI's
additional hidden-subtree freezing behavior is not implemented yet.
See the [Views recipe](cookbook/views.zig) for independent counters and retained pages.

## Update and ownership rules

- All UI and reactive operations run on one UI thread. State reads during `content()`
  register dependencies; subscriptions are replaced only after a successful
  render. Equal State values and equal TextState contents do not notify.
- State changes dirty only the Views that read them. `pump()` flushes after native
  event dispatch, coalescing several writes. Only dirty Views execute `content()`;
  a parent update does not rerun a clean child View. Call `flush()` explicitly in
  tests, `app.invalidate()` for non-reactive root fields, or
  `app.findView(id).?.invalidate()` for non-reactive child fields. Building a
  View cannot mutate State; callbacks cannot recursively flush.
- `ui.subView(&child_model).id("child")` declares a retained virtual subtree
  with its own subscriptions. It can emit zero or more children
  without adding an LVGL wrapper. Ordinary functions accepting builders still
  share their caller's View. Cross-thread posting, computed state and explicit
  freeze/thaw hooks are not implemented yet.
- Ids are unique among siblings. Identity follows CPPUI's `operator==`: same
  kind, same declared grid cell, and the same id when either has one. Siblings
  without ids match by kind in sequence, so removing an earlier sibling of
  another kind keeps the later ones. SubViews also match model type and address;
  changing the model replaces the View. Layout and text changes do not change
  identity. Spacers and Dividers are not movable: they are recreated rather than moved.
- Models, State, Binding contexts and callback contexts are borrowed. They must
  remain at stable addresses and outlive every mounted control using them.
  `State(T)` copies values shallowly; `TextState` owns and copies its bytes.
- Declarations own copies of their ids and text. Builders are valid only during
  that `content()` call.
- A failed build (a declaration error or a failed allocation while declaring)
  keeps the View's mounted tree and subscriptions. A failure during `sync()`
  behaves like a CPPUI exception: what was already reconciled stays, the rest
  of the old tree stays mounted, and the View stays dirty for the next flush.
  Each dirty View redraws on its own, so an error in one View does not undo
  another View's redraw from the same flush.
- A binding setter error is returned by the next `flush()`/`pump()`. The
  owning View remains dirty so a subsequent successful flush restores the model's value.
  Custom bindings must provide a `Signal` for automatic external notifications,
  or explicitly invalidate their owning View.
- `app.find(id)` returns the first depth-first matching native pointer. It is
  borrowed and becomes invalid when removed. Deletion of a whole managed
  control/subtree is observed and remounted on the next flush. Do not delete or
  reparent a control's private internal children.
- Each Application exclusively owns one LVGL/SDL runtime. Destroy it after callbacks
  unwind; `requestQuit()` is safe inside callbacks. Borrowed hosts, multiple
  concurrent Apps and other backends are outside this first version.

`.layout(.{ .width_percent = 100 })` and `.height_percent` size a control
relative to its parent; they are a ZUI addition to PUI's pixel sizes. A pixel
size and a percentage replace each other on the same axis. `.weight` shares
remaining space in an HBox or VBox, like PUI's `weight`. A Spacer takes the
remaining space along its box's axis; a Divider draws a 1-pixel line across it.

`splitter(.{})` contains exactly two panes. Without `.ratio(binding)` it keeps
its own split, like PUI and CPPUI; with a `Binding(u8)` percentage, clamped to
10–90, the model owns it. Drag its divider, or focus it with Tab and use arrow keys.
`.style()` colors and font size can be set on a control or inherited from a
container. LVGL uses the nearest compiled Montserrat size (12, 14, 16, 20 or 24).

## Differences from PUI / CPPUI

- Options are anonymous structs with `snake_case` fields instead of keyword
  arguments; `labelFmt()` formats text without an intermediate allocation.
- `.disabled(bool)` always takes an argument (CPPUI defaults to `true`).
- Percent sizes are ZUI-only. `margin`, `minWidth` / `minHeight`, `fontWeight`
  and `fontFamily` are not implemented yet.
- A Grid child's cell is `.gridCell()`, because `grid()` already declares the
  container. There are no width breakpoints (`wideColumns`, `wideGrid`), and
  columns are equal rather than weighted by their children's expansion.
- Splitters take exactly two panes. Scroll has no `scrollX` / `scrollY` anchoring.
- TextField has no editing-buffer binding or `.input()` / `.change()` events.
- There is no `Views` page selector or `ref()`; use `.visible()` on a container
  around each `subView()` (see the [Views recipe](cookbook/views.zig)).
- Application options (`title`, `width`, `height`) are passed to
  `Application.create()` instead of chained setters.

## Source layout

- `src/core.zig`: public facade for the LVGL-independent node, view, dom and state modules.
- `src/root.zig`: public facade adding the LVGL backend and Application.
- `src/lvgl/`: the LVGL backend and SDL application host.
- `native/`: LVGL configuration and the small C SDL host adapter.
- `examples/main.zig`: counter, form and id-keyed editor list.
- `cookbook/`: gallery, recipe registry, separate recipe sources and smoke tests.
- `src/core_tests.zig`: declarations, deferred errors, reactive state and reconciliation.
- `src/integration_tests.zig`: native widget and lifetime regressions.
- `src/view_tests.zig`: independent View updates, virtual-node layout, failure recovery and visibility.
- `src/testing/backend.zig`: the native-free backend `test-core` checks `sync()` against.

The UI/state logic is Zig. The C adapter handles SDL host setup, orderly quit
and screenshot output; LVGL supplies layout, rendering and native controls.
