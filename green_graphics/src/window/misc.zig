//! Author: palsmo
//! Status: In Progress
//! About: X11 Window Handler

const std = @import("std");
const c = @cImport({
    @cInclude("xcb/xcb.h");
});

const maple = @import("maple_utils");

const mod_shared = @import("./shared.zig");

const XClientError = mod_shared.XClientError;
const assertAndMsg = maple.assert.misc.assertAndMsg;
const panic = std.debug.panic;

/// A lightweight X11 window handler.
/// Uses the 'XCB'-api under the hood.
pub const WindowHandler = struct {
    const Self = @This();

    pub const Options = struct {
        // display identifier, 'null' = value of DISPLAY env_var
        display_label: [*c]const u8 = null,
        // parent window, 'null' = root window
        window_parent_id: ?c.xcb_window_t = null,
        // border width (only suggestion, os may overwrite)
        border_width: u16 = 0,
        // position (outside) for window's top-left corner, (only suggestion, os may overwrite)
        position: struct { x: i16, y: i16 } = .{ .x = 100, .y = 100 },
        // dimension (inside) for window, (only suggestion, os may overwrite)
        dimension: struct { w: u16, h: u16 } = .{ .w = 800, .h = 600 },
    };

    // struct fields
    connection: *c.xcb_connection_t,
    screen_data: *c.xcb_screen_t,
    window_id: c.xcb_window_t,
    metadata: u16,

    const meta_msk_is_init: u8 = 0b0000_0000_0000_0001;
    const meta_msk_is_open: u8 = 0b0000_0000_0000_0010;

    /// Initialize the handler.
    /// Issue key specs:
    /// - Throws error when server connection process fail.
    pub fn init(options: Options) !Self {
        // setup
        const connection = c.xcb_connect(options.display_label, null) orelse return XClientError.FailedToEstablishConnectionWithServer;
        const screen_data = c.xcb_setup_roots_iterator(c.xcb_get_setup(connection)).data;
        const window_parent_id = options.window_parent_id orelse screen_data.*.root;

        // create window
        const window_id = c.xcb_generate_id(connection);
        _ = c.xcb_create_window(
            connection, // struct rep. connection
            c.XCB_COPY_FROM_PARENT, // depth
            window_id, // self
            window_parent_id, // parent
            options.position.x, // x
            options.position.y, // y
            options.dimension.w, // w
            options.dimension.h, // h
            options.border_width, // border width
            c.XCB_WINDOW_CLASS_INPUT_OUTPUT, // class
            screen_data.*.root_visual, // visual
            0, // value/attribute mask
            null, // value/attribute struct
        );

        return .{
            .connection = connection,
            .screen_data = screen_data,
            .window_id = window_id,
            .metadata = meta_msk_is_init,
        };
    }

    /// Destroy the window and disconnect from the server.
    pub fn deinit(self: *Self) void {
        self.assertInit();
        _ = c.xcb_destroy_window(self.connection, self.window_id);
        c.xcb_disconnect(self.connection);
        self.metaReset();
    }

    /// Assert that `self` has called 'init'.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// * most often no reason for the user to call.
    pub inline fn assertInit(self: *const Self) void {
        assertAndMsg(self.metaIsInit(), "WindowHandler hasn't been initialized (call 'init' first).", .{});
    }

    /// Reset handler's metadata to zero.
    /// * most often no reason for the user to call.
    pub inline fn metaReset(self: *Self) void {
        self.metadata = 0;
    }

    /// Check handler's init status.
    /// * most often no reason for the user to call.
    pub inline fn metaInitStatus(self: *const Self) bool {
        return meta_msk_is_init == (self.metadata & meta_msk_is_init);
    }

    /// Set window's open status (set bit in `self.metadata` to `b`).
    /// * most often no reason for the user to call.
    pub inline fn metaOpenSet(self: *Self, b: bool) void {
        if (b) self.metadata |= meta_msk_is_open else self.metadata &= ~meta_msk_is_open;
    }

    /// Check the window's open status.
    pub inline fn metaOpenStatus(self: *const Self) bool {
        return meta_msk_is_open == (self.metadata & meta_msk_is_open);
    }

    /// Get the identifier of the window.
    pub inline fn getId(self: *const Self) c.xcb_window_t {
        return self.window_id;
    }

    /// Get coordinate tuple for window's top-left corner (inside border).
    /// Issue key specs:
    /// - Returns .{ 0, 0 } if `self.window_id` was invalid.
    pub inline fn getXY(self: *const Self) struct { x: i16, y: i16 } {
        self.assertInit();

        // request data
        var e: [*c]c.xcb_generic_error_t = null;
        const geo_cookie = c.xcb_get_geometry(self.connection, self.window_id);
        const geo = c.xcb_get_geometry_reply(self.connection, geo_cookie, &e);
        if (e != null) {
            switch (e.*.error_code) {
                c.XCB_DRAWABLE, c.XCB_WINDOW => return .{ 0, 0 },
                else => unreachable,
            }
        }

        return .{ .x = geo.*.x, .y = geo.*.y };
    }

    /// Get dimension tuple for the window's size (outside border).
    /// Issue key specs:
    /// - Returns .{ 0, 0 } if `self.window_id` was invalid.
    pub inline fn getWH(self: *const Self) struct { w: u16, h: u16 } {
        self.assertInit();

        // request data
        var e: [*c]c.xcb_generic_error_t = null;
        const geo_cookie = c.xcb_get_geometry(self.connection, self.window_id);
        const geo = c.xcb_get_geometry_reply(self.connection, geo_cookie, &e);
        if (e != null) {
            switch (e.*.error_code) {
                c.XCB_DRAWABLE, c.XCB_WINDOW => return .{ 0, 0 },
                else => unreachable,
            }
        }

        return .{ .w = geo.*.width, .h = geo.*.height };
    }

    /// Simple check to verify connection with the server.
    /// * not guaranteed to catch all connection issues.
    pub fn statusConnection(self: *const Self) c_int {
        self.assertInit();
        return c.xcb_connection_has_error(self.connection);
    }

    /// Show the window on screen.
    /// Issue key specs:
    /// - Return-code 0 (ok) always.
    pub fn open(self: *Self) u8 {
        self.assertInit();
        if (self.metaIsOpen()) return 0;

        _ = c.xcb_map_window(self.connection, self.window_id);
        _ = c.xcb_flush(self.connection);

        self.metaSetOpen(true);
        return 0;
    }

    /// Remove the window from screen.
    /// Issue key specs:
    /// - Return-code 0 (ok) always.
    pub fn close(self: *Self) u8 {
        self.assertInit();
        if (!self.metaIsOpen()) return 0;

        _ = c.xcb_unmap_window(self.connection, self.window_id);
        _ = c.xcb_flush(self.connection);

        self.metaSetOpen(false);
        return 0;
    }
    /// Set position `x` and `y` for the window's top-left corner (border excluded).
    /// Value of *null* will have no change in that direction.
    /// Issue key specs:
    /// - Return-code 0 (ok) or 1 (warn) if `self.window_id` was invalid.
    pub fn move(self: *Self, x: ?c_int, y: ?c_int) u8 {
        self.assertInit();
        if (!self.metaIsOpen()) return 0;

        const geo: ?[*c]c.xcb_get_geometry_reply_t = b: {
            if (x == null or y == null) {
                // request data
                var e: [*c]c.xcb_generic_error_t = null;
                const geo_cookie = c.xcb_get_geometry(self.connection, self.window_id);
                const geo = c.xcb_get_geometry_reply(self.connection, geo_cookie, &e);
                if (e != null) {
                    switch (e.*.error_code) {
                        c.XCB_DRAWABLE, c.XCB_WINDOW => return 1,
                        else => unreachable,
                    }
                }
                break :b geo;
            } else {
                break :b null;
            }
        };

        const value_mask = c.XCB_CONFIG_WINDOW_X | c.XCB_CONFIG_WINDOW_Y;
        const value_list = [_]i16{ x orelse geo.?.*.x, y orelse geo.?.*.y };
        _ = c.xcb_configure_window(self.connection, self.window_id, value_mask, &value_list);
        _ = c.xcb_flush(self.connection);

        return 0;
    }

    /// Set dimension `w` and `h` for the window (border is included).
    /// Value of *null* will have no change in that direction.
    /// Issue key specs:
    /// - Return-code 0 (ok) or 1 (warn) if `self.window_id` was invalid.
    pub fn resize(self: *Self, w: ?c_uint, h: ?c_uint) u8 {
        self.assertInit();
        if (!self.metaIsOpen()) return 0;

        const geo: ?[*c]c.xcb_get_geometry_reply_t = b: {
            if (w == null or h == null) {
                // request data
                var e: [*c]c.xcb_generic_error_t = null;
                const geo_cookie = c.xcb_get_geometry(self.connection, self.window_id);
                const geo = c.xcb_get_geometry_reply(self.connection, geo_cookie, &e);
                if (e != null) {
                    switch (e.*.error_code) {
                        c.XCB_DRAWABLE, c.XCB_WINDOW => return 1,
                        else => unreachable,
                    }
                }
                break :b geo;
            } else {
                break :b null;
            }
        };

        const value_mask = c.XCB_CONFIG_WINDOW_WIDTH | c.XCB_CONFIG_WINDOW_HEIGHT;
        const value_list = [_]u16{ w orelse geo.?.*.width, h orelse geo.?.*.height };
        _ = c.xcb_configure_window(self.connection, self.window_id, value_mask, &value_list);
        _ = c.xcb_flush(self.connection);

        return 0;
    }

    /// Raise the window to appear in front on screen.
    /// Issue key specs:
    /// - Return-code 0 (ok) always.
    pub fn raise(self: *const Self) u8 {
        self.assertInit();
        if (!self.metaIsOpen()) return 0;

        const value_mask = c.XCB_CONFIG_WINDOW_STACK_MODE;
        const value_list = [_]c_int{c.XCB_STACK_MODE_ABOVE};
        _ = c.xcb_configure_window(self.connection, self.window_id, value_mask, &value_list);
        _ = c.xcb_flush(self.connection);

        return 0;
    }

    // Set the background color and transparency of the window.
    // `color` is in RGBA format where each component is in the range 0-255.
    // `alpha` is in the range 0-255, where 0 is fully transparent and 255 is fully opaque.
    //pub fn setBackground(self: *const Self, color: struct { r: u8, g: u8, b: u8 }, alpha: u8) void {
    //    self.assertInit();
    //    if (!self.metaIsOpen()) return error.WindowNotOpen;
    //    _ = color;
    //    _ = alpha;
    //}
};

const expectEqual = std.testing.expectEqual;

test WindowHandler {
    var window_handler = try WindowHandler.init(.{});
    defer window_handler.deinit();

    try expectEqual(0, window_handler.statusConnection());
    try expectEqual(true, window_handler.metaIsInit());
    try expectEqual(false, window_handler.metaIsOpen());

    const rc_open = window_handler.open();

    try expectEqual(0, rc_open);
    try expectEqual(true, window_handler.metaIsOpen());

    std.time.sleep(5 * std.time.ns_per_s);
}
