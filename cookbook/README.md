# ZUI Cookbook

Developed after [PUI](https://github.com/buganini/PUI) and
[CPPUI](https://github.com/buganini/CPPUI), following the structure of
[CPPUI's cookbook](https://github.com/buganini/CPPUI/tree/main/cookbook).
This implementation currently targets **LVGL 9.6 / SDL2** with **Zig 0.17.1**.

## Run

From the repository root:

```sh
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0 -- --recipe textfield
zig build run -Dlvgl-dir=../CPPUI/lvgl-9.6.0 -- --list
```

Omit `-Dlvgl-dir` when LVGL is at `deps/lvgl`. `zig build` installs
`zig-out/bin/zui-cookbook` and the smaller `zui-demo` executable.

The window starts at 1024 × 768. Choose a recipe from the scrollable **Examples**
sidebar; the active entry is highlighted. **Code** displays its Zig source and
**Result** contains live controls. Drag the divider to change pane widths, or
focus it with Tab and press an arrow key. The sidebar and panes stay side by
side when the window narrows; each content area scrolls independently.

**Reload** reads the selected recipe's file from disk. The default source
directory is the absolute `cookbook/` path recorded at build time, independent
of the working directory. Use `-Dcookbook-source-dir=/path/to/cookbook` to point
an installed binary at another source tree. Source is plain text, limited to
256 KiB; unavailable or invalid files show the expected path and error.
Reload updates the displayed text only. Rebuild to run modified code.

## Recipes and remaining work

The registry preserves CPPUI's 35 keys and their ordering. `--list` prints
`ported`, `partial` or `not ported`, plus the remaining capability. These are
Zig adaptations of the examples, not a promise of identical C++ APIs.

| Recipe | Demonstrates | Still to port |
| --- | --- | --- |
| VBox / HBox | Spacing, keyed reversal, flex growth | — |
| Label | Conditional greeting, colors, wrapping, literal text | — |
| Button | Actions, disabled state, colors | — |
| Grid | Equal columns, keyed reflow and editable cells | Explicit coordinates and spans |
| Checkbox | Shared boolean binding and disabled mirrors | Collection membership |
| TextField | Immediate two-way text binding and shared editors | Editing buffer, numeric conversion |
| Scroll | Dynamic keyed rows and retained scroll position | Offset API and end anchoring |
| State Binding | External getter/setter, notifications, latest 100 setter logs | Radio / combobox examples |
| Splitter | Nested horizontal / vertical two-pane splitters | More than two panes per splitter |

Unported recipes stay visible with a description of the missing capability.
Each page owns a separate keyed widget subtree. Navigation destroys the previous
page's controls but keeps its model values; changing columns or order within a
page preserves keyed control identity and editor caret position.

## Structure and checks

- `gallery.zig`: navigation, source reload and Code / Result layout.
- `recipes.zig`: recipe registration and capability status.
- `<key>.zig`: UI declarations and callbacks for one recipe.
- `model.zig`: model lifetime and external binding storage.
- `source.zig`: runtime source loader using `std.Io`.
- `tests.zig`: native events and assertions, kept out of interactive recipes.
- `capture.zig`: headless screenshots of implemented pages and a fallback page.

```sh
zig build test -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build memcheck -Dlvgl-dir=../CPPUI/lvgl-9.6.0
zig build snapshot -Dlvgl-dir=../CPPUI/lvgl-9.6.0
```

These use SDL's dummy/software drivers and do not need a desktop session.
Snapshots are written to `.build/cookbook-<key>.bmp`. The checks exercise every
sidebar entry, live bindings, keyed reflow, navigation state, a narrower window,
source reload, missing/invalid files and bounded external-binding logs.
