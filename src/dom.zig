const std = @import("std");
const c = @import("c");
const core = @import("core");
const Allocator = std.mem.Allocator;
const Declaration = core.Node;

const Mounted = struct {
    app: *Dom,
    object: ?*c.lv_obj_t = null,
    label: ?*c.lv_obj_t = null,
    handle: ?*c.lv_obj_t = null,
    declaration: *Declaration,
    children: std.ArrayListUnmanaged(*Mounted) = std.ArrayListUnmanaged(*Mounted).empty,
};

const Plan = struct {
    mounted: *Mounted,
    declaration: *Declaration,
    is_new: bool,
    children: []*Plan = &.{},
    prepared: usize = 0,
    columns: ?[*]const i32 = null,
    rows: ?[*]const i32 = null,
};

/// Owns retained LVGL objects and reconciles prepared View declarations.
pub const Dom = struct {
    allocator: Allocator,
    view: core.View,
    root: ?*Mounted = null,
    busy: bool = false,
    dispatch_depth: usize = 0,
    event_error: ?anyerror = null,
    render_count: usize = 0,

    pub fn init(allocator: Allocator, model: anytype) Dom {
        return .{ .allocator = allocator, .view = core.View.init(allocator, core.view.Content.init(model)) };
    }
    pub fn deinit(self: *Dom) void {
        std.debug.assert(!self.busy and self.dispatch_depth == 0);
        self.busy = true;
        if (self.root) |root| self.destroyMounted(root);
        self.view.deinit();
    }
    pub fn invalidate(self: *Dom) void {
        self.view.invalidate();
    }
    pub fn flush(self: *Dom) !void {
        if (self.busy or self.dispatch_depth != 0) return error.ReentrantFlush;
        if (self.event_error) |err| {
            self.event_error = null;
            return err;
        }
        if (!self.view.observer.dirty) return;
        self.busy = true;
        defer self.busy = false;
        const next = try self.view.prepare();
        errdefer next.destroy();
        const plan = try self.prepare(self.root, &next.root, c.lv_screen_active().?, next.arena.allocator());
        self.commit(plan);
        if (self.root) |old_root| {
            if (old_root != plan.mounted) self.destroyMounted(old_root);
        }
        self.root = plan.mounted;
        self.view.commit(next);
        self.render_count += 1;
    }

    /// Returns the first depth-first matching key. This pointer is borrowed and
    /// invalid after removal. Native deletion is observed and remounted on flush.
    pub fn find(self: *Dom, key: []const u8) ?*c.lv_obj_t {
        return if (self.root) |root| findIn(root, key) else null;
    }
    fn findIn(mounted: *Mounted, key: []const u8) ?*c.lv_obj_t {
        if (mounted.declaration.options.key) |own| {
            if (std.mem.eql(u8, key, own)) return mounted.object;
        }
        for (mounted.children.items) |child| {
            if (findIn(child, key)) |found| return found;
        }
        return null;
    }

    fn createMounted(self: *Dom, declaration: *Declaration, parent: *c.lv_obj_t) !*Mounted {
        const mounted = try self.allocator.create(Mounted);
        errdefer self.allocator.destroy(mounted);
        mounted.* = .{ .app = self, .declaration = declaration };
        const object = switch (declaration.kind) {
            .label => c.lv_label_create(parent),
            .button => c.lv_button_create(parent),
            .checkbox => c.lv_checkbox_create(parent),
            .text_field => c.lv_textarea_create(parent),
            else => c.lv_obj_create(parent),
        } orelse return error.NativeCreateFailed;
        errdefer c.lv_obj_delete(object);
        mounted.object = object;
        c.lv_obj_add_flag(object, c.LV_OBJ_FLAG_HIDDEN);
        if (declaration.kind == .button)
            mounted.label = c.lv_label_create(object) orelse return error.NativeCreateFailed;
        if (declaration.kind == .text_field) c.lv_textarea_set_one_line(object, true);
        if (declaration.kind == .splitter) {
            const handle = c.lv_obj_create(object) orelse return error.NativeCreateFailed;
            mounted.handle = handle;
            c.lv_obj_remove_flag(handle, c.LV_OBJ_FLAG_SCROLLABLE);
            c.lv_obj_set_style_pad_all(handle, 0, 0);
            c.lv_obj_set_style_border_width(handle, 0, 0);
            c.lv_obj_set_style_radius(handle, 3, 0);
            c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0xa7b4c2), 0);
            c.lv_obj_set_style_bg_color(handle, c.lv_color_hex(0x2196f3), c.LV_STATE_FOCUSED);
            c.lv_obj_set_ext_click_area(handle, 4);
            c.lv_group_add_obj(c.lv_group_get_default(), handle);
            _ = c.lv_obj_add_event_cb(handle, splitterCallback, c.LV_EVENT_ALL, mounted);
        }
        _ = c.lv_obj_add_event_cb(object, eventCallback, c.LV_EVENT_ALL, mounted);
        return mounted;
    }

    fn prepare(self: *Dom, previous: ?*Mounted, declaration: *Declaration, parent: *c.lv_obj_t, arena: Allocator) anyerror!*Plan {
        const old = if (previous) |node| (if (node.object != null) node else null) else null;
        const plan = try arena.create(Plan);
        plan.* = .{
            .mounted = old orelse try self.createMounted(declaration, parent),
            .declaration = declaration,
            .is_new = old == null,
        };
        errdefer self.discard(plan);
        // An externally deleted native subtree still has Zig records. They are
        // retired during commit, while new records are staged independently.
        const children = declaration.children.items;
        plan.children = try arena.alloc(*Plan, children.len);
        try plan.mounted.children.ensureTotalCapacity(self.allocator, children.len);
        if (declaration.kind == .grid) {
            const count = declaration.options.columns;
            const columns = try arena.alloc(i32, @as(usize, count) + 1);
            for (columns[0..count]) |*entry| entry.* = c.LV_GRID_FR(1);
            columns[count] = c.LV_GRID_TEMPLATE_LAST;
            const row_count = @max(1, (children.len + count - 1) / count);
            const rows = try arena.alloc(i32, row_count + 1);
            for (rows[0..row_count]) |*entry| entry.* = c.LV_GRID_CONTENT;
            rows[row_count] = c.LV_GRID_TEMPLATE_LAST;
            plan.columns = columns.ptr;
            plan.rows = rows.ptr;
        }
        for (children, 0..) |child, index| {
            var match: ?*Mounted = null;
            if (old) |node| {
                for (node.children.items, 0..) |candidate, old_index| {
                    if (core.sameIdentity(candidate.declaration, child, old_index, index)) {
                        match = candidate;
                        break;
                    }
                }
            }
            plan.children[index] = try self.prepare(match, child, plan.mounted.object.?, arena);
            plan.prepared += 1;
        }
        return plan;
    }

    fn discard(self: *Dom, plan: *Plan) void {
        for (plan.children[0..plan.prepared]) |child| self.discard(child);
        if (plan.is_new) self.destroyMounted(plan.mounted);
    }
    fn destroyMounted(self: *Dom, mounted: *Mounted) void {
        for (mounted.children.items) |child| self.destroyMounted(child);
        mounted.children.deinit(self.allocator);
        if (mounted.object) |object| {
            _ = c.lv_obj_remove_event_cb_with_user_data(object, eventCallback, mounted);
            c.lv_obj_delete(object);
        }
        self.allocator.destroy(mounted);
    }

    fn commit(self: *Dom, plan: *Plan) void {
        const mounted = plan.mounted;
        for (mounted.children.items) |child| {
            var retained = false;
            for (plan.children) |next| {
                if (next.mounted == child) {
                    retained = true;
                    break;
                }
            }
            if (!retained) self.destroyMounted(child);
        }
        self.update(plan);
        mounted.declaration = plan.declaration;
        mounted.children.clearRetainingCapacity();
        for (plan.children, 0..) |child, index| {
            self.commit(child);
            mounted.children.appendAssumeCapacity(child.mounted);
            c.lv_obj_move_to_index(child.mounted.object.?, @intCast(index));
            if (plan.declaration.kind == .splitter) {
                const vertical = plan.declaration.options.vertical;
                c.lv_obj_set_size(child.mounted.object.?, if (vertical) c.lv_pct(100) else 0, if (vertical) 0 else c.lv_pct(100));
                const ratio = plan.declaration.split_ratio;
                c.lv_obj_set_flex_grow(child.mounted.object.?, if (index == 0) ratio else 100 - ratio);
            }
            if (plan.declaration.kind == .grid) {
                const columns = plan.declaration.options.columns;
                c.lv_obj_set_grid_cell(child.mounted.object.?, c.LV_GRID_ALIGN_STRETCH, @intCast(index % columns), 1, c.LV_GRID_ALIGN_START, @intCast(index / columns), 1);
            }
        }
        if (mounted.handle) |handle| c.lv_obj_move_to_index(handle, 1);
        c.lv_obj_remove_flag(mounted.object.?, c.LV_OBJ_FLAG_HIDDEN);
    }

    fn update(_: *Dom, plan: *Plan) void {
        const mounted = plan.mounted;
        const object = mounted.object.?;
        const declaration = plan.declaration;
        const options = declaration.options;
        const container = switch (declaration.kind) {
            .root, .column, .row, .grid, .scroll, .splitter => true,
            else => false,
        };
        if (container) {
            c.lv_obj_set_style_border_width(object, 0, 0);
            c.lv_obj_set_style_radius(object, 0, 0);
            c.lv_obj_set_style_pad_all(object, options.padding, 0);
            c.lv_obj_set_style_pad_row(object, options.gap, 0);
            c.lv_obj_set_style_pad_column(object, options.gap, 0);
            if (declaration.kind == .grid) {
                c.lv_obj_set_grid_dsc_array(object, plan.columns.?, plan.rows.?);
            } else {
                const horizontal = declaration.kind == .row or (declaration.kind == .splitter and !options.vertical);
                c.lv_obj_set_flex_flow(object, if (horizontal) c.LV_FLEX_FLOW_ROW else c.LV_FLEX_FLOW_COLUMN);
            }
            if (declaration.kind != .scroll and declaration.kind != .root)
                c.lv_obj_remove_flag(object, c.LV_OBJ_FLAG_SCROLLABLE);
        }
        const width = if (options.width_percent) |percent| c.lv_pct(percent) else options.width orelse (if (container or declaration.kind == .text_field) c.lv_pct(100) else c.LV_SIZE_CONTENT);
        const height = if (options.height_percent) |percent| c.lv_pct(percent) else options.height orelse (switch (declaration.kind) {
            .root => c.lv_pct(100),
            .scroll => 200,
            else => c.LV_SIZE_CONTENT,
        });
        c.lv_obj_set_size(object, width, height);
        c.lv_obj_set_flex_grow(object, options.grow);
        c.lv_obj_set_state(object, c.LV_STATE_DISABLED, options.disabled);
        c.lv_obj_set_state(object, c.LV_STATE_CHECKED, options.selected);
        if (options.text_color) |color| {
            c.lv_obj_set_style_text_color(object, c.lv_color_hex(color), 0);
        } else _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_TEXT_COLOR, 0);
        if (options.background) |color| {
            c.lv_obj_set_style_bg_color(object, c.lv_color_hex(color), 0);
            c.lv_obj_set_style_bg_opa(object, c.LV_OPA_COVER, 0);
        } else {
            _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_BG_COLOR, 0);
            _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_BG_OPA, 0);
        }
        if (options.small_text) {
            c.lv_obj_set_style_text_font(object, &c.lv_font_montserrat_12, 0);
        } else _ = c.lv_obj_remove_local_style_prop(object, c.LV_STYLE_TEXT_FONT, 0);
        if (mounted.handle) |handle|
            c.lv_obj_set_size(handle, if (options.vertical) c.lv_pct(100) else 8, if (options.vertical) 8 else c.lv_pct(100));
        switch (declaration.kind) {
            .label => c.lv_label_set_text(object, declaration.text.ptr),
            .button => {
                c.lv_label_set_text(mounted.label.?, declaration.text.ptr);
                c.lv_obj_center(mounted.label.?);
            },
            .checkbox => {
                c.lv_checkbox_set_text(object, declaration.text.ptr);
                c.lv_obj_set_state(object, c.LV_STATE_CHECKED, declaration.checked);
            },
            .text_field => {
                // Preserve caret and selection when a redraw doesn't change text.
                const current = std.mem.span(c.lv_textarea_get_text(object));
                if (!std.mem.eql(u8, current, declaration.text))
                    c.lv_textarea_set_text(object, declaration.text.ptr);
            },
            else => {},
        }
    }

    fn eventCallback(event: ?*c.lv_event_t) callconv(.c) void {
        const e = event orelse return;
        const mounted: *Mounted = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
        const app = mounted.app;
        const code = c.lv_event_get_code(e);
        if (code == c.LV_EVENT_DELETE) {
            mounted.object = null;
            mounted.label = null;
            mounted.handle = null;
            app.invalidate();
            return;
        }
        if (app.busy) return;
        const object = mounted.object orelse return;
        // Copy every callback/binding before invoking user code. Reconciliation
        // is deferred until dispatch unwinds, including nested native events.
        const declaration = mounted.declaration.*;
        app.dispatch_depth += 1;
        defer app.dispatch_depth -= 1;
        if (code == c.LV_EVENT_CLICKED and declaration.kind == .button) {
            if (declaration.options.on_click) |cb| cb.invoke(cb.context) catch |err| {
                app.event_error = err;
                app.invalidate();
            };
        } else if (code == c.LV_EVENT_VALUE_CHANGED) {
            if (declaration.bool_binding) |binding| {
                binding.set(c.lv_obj_has_state(object, c.LV_STATE_CHECKED)) catch |err| {
                    app.event_error = err;
                    app.invalidate();
                };
            }
            if (declaration.text_binding) |binding| {
                binding.set(std.mem.span(c.lv_textarea_get_text(object))) catch |err| {
                    app.event_error = err;
                    app.invalidate();
                };
            }
        }
    }

    fn splitterCallback(event: ?*c.lv_event_t) callconv(.c) void {
        const e = event orelse return;
        const mounted: *Mounted = @ptrCast(@alignCast(c.lv_event_get_user_data(e) orelse return));
        const app = mounted.app;
        if (app.busy) return;
        const object = mounted.object orelse return;
        const declaration = mounted.declaration.*;
        const binding = declaration.split_binding orelse return;
        const code = c.lv_event_get_code(e);
        var ratio: i32 = std.math.clamp(binding.read(binding.context), 10, 90);
        if (code == c.LV_EVENT_PRESSING) {
            const indev = c.lv_indev_active() orelse return;
            var point: c.lv_point_t = undefined;
            c.lv_indev_get_point(indev, &point);
            var area: c.lv_area_t = undefined;
            c.lv_obj_get_content_coords(object, &area);
            const vertical = declaration.options.vertical;
            const size = (if (vertical) area.y2 - area.y1 else area.x2 - area.x1) + 1;
            if (size <= 0) return;
            const offset = if (vertical) point.y - area.y1 else point.x - area.x1;
            ratio = @divTrunc(offset * 100, size);
        } else if (code == c.LV_EVENT_KEY) {
            const key = c.lv_event_get_key(e);
            if (key == c.LV_KEY_LEFT or key == c.LV_KEY_UP) ratio -= 5 else if (key == c.LV_KEY_RIGHT or key == c.LV_KEY_DOWN) ratio += 5 else return;
        } else return;
        app.dispatch_depth += 1;
        defer app.dispatch_depth -= 1;
        binding.set(@intCast(std.math.clamp(ratio, 10, 90))) catch |err| {
            app.event_error = err;
            app.invalidate();
        };
    }
};
