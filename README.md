# ZUI

ZUI is a declarative UI framework in Zig, developed after
[PUI (Python)](https://github.com/buganini/PUI) and
[CPPUI (C++)](https://github.com/buganini/CPPUI).
It currently targets **LVGL**, with an SDL2 desktop host on Linux.

The first working version includes reactive state and two-way bindings,
keyed widget reuse, HBox/VBox, Grid, Scroll, Splitter, Label, Button, Checkbox and TextField.
The [cookbook](cookbook/README.md) follows
[CPPUI's cookbook](https://github.com/buganini/CPPUI/tree/main/cookbook): a
scrollable example list, draggable Code / Result panes and runtime source reload.
Ten interactive recipes are available; the remaining pages show their missing
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
subtree deletion, deferred SDL quit, splitter pointer/keyboard resizing, cookbook navigation,
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
    var column = ui.vbox(.{ .padding = 12, .gap = 8 });
    column.labelFmt("Count: {d}", .{self.count.get(ui)}, .{});
    column.button("+", .{
        .key = "increment",
        .on_click = zui.callback(self, increment),
    });
}

fn increment(self: *Counter) !void {
    try self.count.set(self.count.peek() + 1);
}
```

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

## Update and ownership rules

- All UI and reactive operations run on one UI thread. State reads during `content()`
  register dependencies; subscriptions are replaced only after a successful
  render. Equal State values and equal TextState contents do not notify.
- State changes mark the root dirty. `pump()` flushes after native event
  dispatch, coalescing several writes. Call `flush()` explicitly in tests or
  `invalidate()` after changing non-reactive model fields. Building a view
  cannot mutate State; callbacks cannot recursively flush.
- This version has one reactive root per App. Reusable components are ordinary
  functions accepting builders. Independently scheduled retained subviews,
  cross-thread posting and computed-state APIs are not implemented yet.
- Keys are unique among siblings. Identity is **kind + key**; unkeyed children
  use **kind + position**. Layout and text changes do not change identity.
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
- A binding setter error is returned by the next `flush()`/`pump()`. The root
  remains dirty so a subsequent successful flush restores the model's value.
  Custom bindings must provide a `Signal` for automatic external notifications,
  or arrange for `app.invalidate()` themselves.
- `app.find(key)` returns the first depth-first matching native pointer. It is
  borrowed and becomes invalid when removed. Deletion of a whole managed
  control/subtree is observed and remounted on the next flush. Do not delete or
  reparent a control's private internal children.
- Each App exclusively owns one LVGL/SDL runtime. Destroy it after callbacks
  unwind; `requestQuit()` is safe inside callbacks. Borrowed hosts, multiple
  concurrent Apps and other backends are outside this first version.

`width_percent` and `height_percent` size a control relative to its parent;
use either a percentage or a pixel size on each axis. `splitter(binding, options)`
contains exactly two panes and takes a `Binding(u8)` percentage, clamped to
10–90. It owns the panes' sizes and flex weights. Set `vertical = true` to stack
panes. Drag its divider, or focus it with Tab and use arrow keys. Text/background
colors and `small_text` can be set on a control or inherited from a container.

## Source layout

- `src/core.zig`: declarations, identity, state, bindings and dependencies.
- `src/root.zig`: retained LVGL tree, reconciliation, event dispatch and App.
- `native/`: LVGL configuration and the small C SDL host adapter.
- `examples/main.zig`: counter, form and keyed editor list.
- `cookbook/`: gallery, recipe registry, separate recipe sources and smoke tests.
- `src/integration_tests.zig`: native widget and lifetime regressions.

The UI/state logic is Zig. The C adapter handles SDL host setup, orderly quit
and screenshot output; LVGL supplies layout, rendering and native controls.
