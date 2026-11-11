# ZUI

A Zig declarative UI framework developed after PUI/CPPUI, targeting LVGL.

Requires Zig 0.17.1. The core provides a declaration builder, keyed identity,
reactive State/Binding, owned TextState and transactional dependency replacement.

```sh
zig build test-core
```

State and callback contexts are borrowed and must have stable addresses. All UI
and reactive operations run on the UI thread. Builders live for one render only.
