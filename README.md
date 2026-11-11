# ZUI

ZUI is a declarative UI framework in Zig, developed after
[PUI (Python)](https://github.com/buganini/PUI) and
[CPPUI (C++)](https://github.com/buganini/CPPUI).
It currently targets **LVGL**, with an SDL2 desktop host on Linux.

The first working version includes reactive state and two-way bindings,
independent retained Views, keyed widget reuse, HBox/VBox, Grid, Scroll, Splitter, Label, Button, Checkbox and TextField.
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
    const column = ui.vbox().padding(12).gap(8);
    _ = column.labelFmt("Count: {d}", .{self.count.get(ui)});
    _ = column.button("+").key("increment").onClick(zui.callback(self, increment));
}

fn increment(self: *Counter) !void {
    try self.count.set(self.count.peek() + 1);
}
```

Every widget, container and View declaration returns a `Builder` handle.
Modifiers return the same handle for chaining; use `_ =` when its result is not
needed, or keep a `const` handle to add children to a container. Copies refer to
the same snapshot node, so configuring a copy updates that declaration too.
Factories take only their content or binding arguments; configuration uses
methods such as `.key()`, `.visible()`, `.widthPercent()` and `.onClick()`.
The former options argument has been removed. Methods use Zig's `lowerCamelCase`;
type names remain `TitleCase`.

Valid repeated settings use the last value. Invalid settings latch the first
error even if a later setter would correct them. Keys are copied and checked
against siblings on every `.key()` call. Leaf controls cannot contain children;
virtual Views accept `.key()` and take layout/visibility from their physical
containers. Invalid modifiers are reported at the same deferred error boundary.

Widget declarations and tracked reads do not need `try`. All builders in one
`content()` call share its first declaration error, including allocation failures
while formatting text or tracking dependencies. After a failure, subsequent UI
declarations do nothing, and failed containers remain safe to use. State and
explicit Binding reads still return real values so conditions and loops can
finish normally. Custom binding getters must be free of side effects.

App checks the error after `content()` returns, before changing subscriptions or
native widgets. A failed render preserves the previous UI and subscriptions;
`flush()` / `pump()` returns the error. The next attempt starts with a fresh
error record. Ordinary Zig code in `content()` still executes after a declaration
failure, so keep application side effects in event callbacks.

Use `ui.fail(err)` to report a custom declaration error. Models may also return
`!void` for their own fallible operations; App captures that error at the same
boundary, preserving any earlier Builder error. Model initialization, State
writes in callbacks, and App operations remain explicitly fallible.

Create state with `zui.State(i32).init(allocator, 0)` and call `deinit()` after
its App is destroyed. Editable text uses `try zui.TextState.init(allocator, text)`.
Both provide `.binding()` for controls. See [the complete demo](examples/main.zig)
for model setup, teardown and all supported widgets.

```zig
const app = try zui.App.create(allocator, &model, .{ .title = "My application" });
defer app.destroy();
try app.run();
```

## Architecture

| Module | Responsibility |
| --- | --- |
| [`node.zig`](src/node.zig) | Logical nodes, identity, options, Builder and owned declaration snapshots |
| [`view.zig`](src/view.zig) | One model's `content()`, reactive subscriptions and prepare/commit lifecycle |
| [`dom.zig`](src/dom.zig) | Retained LVGL objects, virtual-node flattening, reconciliation and native events |
| [`state.zig`](src/state.zig) | State, bindings, signals and observers |
| [`app.zig`](src/app.zig) | SDL/LVGL host, event loop and DOM ownership |

`root.zig` exposes these modules as `zui.node`, `zui.view`, `zui.dom` and
`zui.state`, as well as the usual top-level types. `core.zig` exposes the parts
that work without LVGL. Each View finishes its content and checks deferred
errors before DOM preparation. All affected Views commit together only after
preparation succeeds; a failed child leaves every previous snapshot and
subscription intact. DOM traversal currently visits the retained tree even
when only one View is dirty.

```zig
pub fn content(self: *Window, ui: *zui.Builder) void {
    const page = ui.vbox().visible(self.show_counter.get(ui));
    _ = page.view(&self.counter).key("counter");
}
```

All widgets and physical containers provide `.visible(bool)` (default `true`).
`.visible(false)` hides a retained control and excludes it from layout;
showing it again preserves its identity and unchanged editor caret. An `if`
around the declaration instead removes and later remounts it. Virtual Views
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
  `app.findView(key).?.invalidate()` for non-reactive child fields. Building a
  View cannot mutate State; callbacks cannot recursively flush.
- `ui.view(&child_model).key("child")` declares a retained virtual subtree
  with its own subscriptions and snapshot. It can emit zero or more children
  without adding an LVGL wrapper. Ordinary functions accepting builders still
  share their caller's View. Cross-thread posting, computed state and explicit
  freeze/thaw hooks are not implemented yet.
- Keys are unique among siblings. Identity is **kind + key**; unkeyed children
  use **kind + position**. Views also match model type and address; changing the
  model replaces the View. Layout and text changes do not change identity.
  Matching currently uses a linear search per child, so very large reordered
  lists may require a future indexing optimization.
- Models, State, Binding contexts and callback contexts are borrowed. They must
  remain at stable addresses and outlive every mounted control using them.
  `State(T)` copies values shallowly; `TextState` owns and copies its bytes.
- Declaration keys and text are copied into a render arena. Builders are valid
  only during that `content()` call. Mounted nodes are separately allocated and retain
  their native identity across renders.
- Build or Zig allocation failure keeps the previous tree and subscriptions.
  New native controls are staged hidden until preparation succeeds. LVGL's
  internal allocation/assertion failures are not a fully recoverable transaction.
- A binding setter error is returned by the next `flush()`/`pump()`. The
  owning View remains dirty so a subsequent successful flush restores the model's value.
  Custom bindings must provide a `Signal` for automatic external notifications,
  or explicitly invalidate their owning View.
- `app.find(key)` returns the first depth-first matching native pointer. It is
  borrowed and becomes invalid when removed. Deletion of a whole managed
  control/subtree is observed and remounted on the next flush. Do not delete or
  reparent a control's private internal children.
- Each App exclusively owns one LVGL/SDL runtime. Destroy it after callbacks
  unwind; `requestQuit()` is safe inside callbacks. Borrowed hosts, multiple
  concurrent Apps and other backends are outside this first version.

`widthPercent()` and `heightPercent()` size a control relative to its parent.
`width()` / `height()` use pixels; the last size setter replaces the previous
unit on that axis. `splitter(binding)` contains exactly two panes and takes a
`Binding(u8)` percentage, clamped to 10–90. It owns the panes' sizes and flex weights. Call `.vertical(true)` to stack
panes. Drag its divider, or focus it with Tab and use arrow keys.
`.textColor()`, `.background()` and `.smallText()` can be set on a control
or inherited from a container.

## Source layout

- `src/core.zig`: public facade for the LVGL-independent node, view and state modules.
- `src/root.zig`: public facade adding the LVGL DOM and App modules.
- `native/`: LVGL configuration and the small C SDL host adapter.
- `examples/main.zig`: counter, form and keyed editor list.
- `cookbook/`: gallery, recipe registry, separate recipe sources and smoke tests.
- `src/core_tests.zig`: declarations, deferred errors and reactive-state checks.
- `src/integration_tests.zig`: native widget and lifetime regressions.
- `src/view_tests.zig`: independent View updates, virtual-node layout, rollback and visibility.

The UI/state logic is Zig. The C adapter handles SDL host setup, orderly quit
and screenshot output; LVGL supplies layout, rendering and native controls.
