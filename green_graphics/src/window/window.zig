//! Author: palsmo
//! Status: In Progress
//! About: XServer Window Handler

const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
});

const maple = @import("maple_utils");

const mod_shared = @import("./shared.zig");

const XClientError = mod_shared.XClientError;
const assertAndMsg = maple.assert.misc.assertAndMsg;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Handler for an X11 window.
pub const WindowHandler = struct {
    const Self = @This();

    pub const Options = struct {
        // display label, 'null' = value of DISPLAY env_var
        display_str: [*c]const u8 = null,
        // parent window, 'null' = root window
        window_parent_id: ?c.Window = null,
        // border width (only suggestion, os may overwrite)
        border_width: c_uint = 0,
        // position (outside) for window's top-left corner, (only suggestion, os may overwrite)
        position: struct { x: c_int, y: c_int } = .{ .x = 100, .y = 100 },
        // dimension (inside) for window, (only suggestion, os may overwrite)
        dimension: struct { w: c_uint, h: c_uint } = .{ .w = 800, .h = 600 },
    };

    // struct fields
    x_connection: *c.Display,
    screen_id: c_int,
    window_parent_id: c.Window,
    window_id: c.Window,
    attributes_cached: c.XWindowAttributes,
    metadata: u8,

    const meta_msk_is_initialized: u8 = 0b0000_0001;
    const meta_msk_is_open: u8 = 0b0000_0010;

    /// Initialize the handler by connecting to XServer.
    /// Issue key specs:
    /// - Throws error when connection process fail.
    pub fn init(options: Options) !Self {
        const x_connection = c.XOpenDisplay(options.display_str) orelse {
            return XClientError.FailedToEstablishConnectionWithServer;
        };
        const screen_id = c.XDefaultScreen(x_connection);
        const window_parent_id = options.window_parent_id orelse c.XRootWindow(x_connection, screen_id);

        var set_attributes: c.XSetWindowAttributes = .{
            .background_pixel = c.XBlackPixel(x_connection, screen_id),
            .event_mask = c.ExposureMask | c.KeyPressMask,
        };

        const window_id = c.XCreateWindow(
            x_connection,
            window_parent_id,
            options.position.x,
            options.position.y,
            options.dimension.w,
            options.dimension.h,
            0, // border width
            c.CopyFromParent, // depth
            c.InputOutput, // class
            null, // visual
            c.CWBackPixel | c.CWEventMask,
            &set_attributes,
        );

        var attributes: c.XWindowAttributes = undefined;
        _ = c.XGetWindowAttributes(x_connection, window_id, &attributes); // status irrelevant

        return .{
            .x_connection = x_connection,
            .screen_id = screen_id,
            .window_parent_id = window_parent_id,
            .window_id = window_id,
            .attributes_cached = attributes,
            .metadata = meta_msk_is_initialized,
        };
    }

    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub fn deinit(self: *Self) void {
        self.assertInitialized();
        const status_xdw = c.XDestroyWindow(self.x_connection, self.window_id);
        if (status_xdw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XCloseDisplay(self.x_connection); // status irrelevant
        self.metaSetInitialized(false);
    }

    /// Assert that `self` has called 'init'.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// * practically no reason for the user to call
    pub inline fn assertInitialized(self: *const Self) void {
        assertAndMsg(self.metaIsInitialized(), "WindowHandler hasn't been initialized (call 'init' first).", .{});
    }

    /// Check handler's init status.
    /// * practically no reason for the user to call
    pub inline fn metaIsInitialized(self: *const Self) bool {
        return meta_msk_is_initialized == (self.metadata & meta_msk_is_initialized);
    }

    /// Set handler's init status (set bit in `self.metadata` to `b`).
    /// * practically no reason for the user to call
    pub inline fn metaSetInitialized(self: *Self, b: bool) void {
        if (b) self.metadata |= meta_msk_is_initialized else self.metadata &= ~meta_msk_is_initialized;
    }

    /// Check window's open status.
    pub inline fn metaIsOpen(self: *const Self) bool {
        return meta_msk_is_open == (self.metadata & meta_msk_is_open);
    }

    /// Set window's open status (set bit in `self.metadata` to `b`).
    /// * practically no reason for the user to call
    pub inline fn metaSetOpen(self: *Self, b: bool) void {
        if (b) self.metadata |= meta_msk_is_open else self.metadata &= ~meta_msk_is_open;
    }

    /// Reset `self.metadata`.
    /// * practically no reason for the user to call
    pub inline fn metaReset(self: *Self) void {
        self.metadata = 0;
    }

    /// Refresh the `self.attributes_cached`.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub fn refreshCachedAttributes(self: *Self) void {
        self.assertInitialized();
        const status_xgwa = c.XGetWindowAttributes(self.x_connection, self.window_id, &self.attributes_cached);
        if (status_xgwa == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
    }

    /// Get coordinate tuple for window's top-left corner (inside border).
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub inline fn getXY(self: *const Self) struct { x: c_int, y: c_int } {
        self.assertInitialized();
        return .{ .x = self.attributes_cached.x, .y = self.attributes_cached.y };
    }

    /// Get dimension tuple for the window's size (outside border).
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub fn getWH(self: *const Self) struct { w: c_uint, h: c_uint } {
        self.assertInitialized();
        return .{ .w = self.attributes_cached.width, .h = self.attributes_cached.height };
    }

    /// Show the window.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self` window is already visible.
    pub fn open(self: *Self) void {
        self.assertInitialized();
        if (self.metaIsOpen()) panic("Invalid call to 'open' window, has no effect since the window is already open.", .{});
        const status_xmw = c.XMapWindow(self.x_connection, self.window_id); // status irrelevant
        if (status_xmw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        self.refreshCachedAttributes(); // 'map_state' changes, (os may also have modified)
        self.metaSetOpen(true);
    }

    /// Hide the window.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self` window is already hidden.
    pub fn close(self: *Self) void {
        self.assertInitialized();
        if (!self.metaIsOpen()) panic("Invalid call to 'close' window, has no effect since the window is already closed.", .{});
        const status_xuw = c.XUnmapWindow(self.x_connection, self.window_id);
        if (status_xuw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        self.refreshCachedAttributes(); // 'map_state' changes
        self.metaSetOpen(false);
    }

    /// Set position `x` and `y` for the window's top-left corner.
    /// Value of *null* will have no change in that direction (takes value in `self.attributes_cached`).
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self` window hasn't been opened.
    pub fn move(self: *Self, x: ?c_int, y: ?c_int) void {
        self.assertInitialized();
        if (!self.metaIsOpen()) panic("Invalid call to 'move' window, has no effect since the window is closed.", .{});
        const _x = x orelse self.attributes_cached.x;
        const _y = y orelse self.attributes_cached.y;
        const status_xmw = c.XMoveWindow(self.x_connection, self.window_id, _x, _y);
        if (status_xmw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        self.refreshCachedAttributes(); // 'x' and 'y' changes, (os may also have modified)
    }

    /// Set dimension `w` and `h` for the window.
    /// Value of *null* will have no change in that direction (takes value in `self.attributes_cached`).
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self` window hasn't been opened.
    pub fn resize(self: *Self, w: ?c_uint, h: ?c_uint) void {
        self.assertInitialized();
        if (!self.metaIsOpen()) panic("Invalid call to 'resize' window, has no effect since the window is closed.", .{});
        const _w = w orelse @as(c_uint, @intCast(self.attributes_cached.width)); // for some reason 'width' is c_int here
        const _h = h orelse @as(c_uint, @intCast(self.attributes_cached.height)); // for some reason 'height' is c_int here
        const status_xrw = c.XResizeWindow(self.x_connection, self.window_id, _w, _h);
        if (status_xrw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        self.refreshCachedAttributes(); // 'width' and 'height' changes, (os may also have modified)
    }

    /// Raise the window to appear in front.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self` window hasn't been opened.
    pub fn raise(self: *const Self) void {
        self.assertInitialized();
        if (!self.metaIsOpen()) panic("Invalid call to `raise` window, has no effect since the window is closed.", .{});
        const status_xrw = c.XRaiseWindow(self.x_connection, self.window_id);
        if (status_xrw == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        // z-value is not stored as part of 'XWindowAttributes'
    }

    /// Raise the window and windows with `self` as parent to appear in front.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub fn raiseAll(self: *const Self) void {
        self.assertInitialized();
        const status_xmr = c.XMapRaised(self.x_connection, self.window_id);
        if (status_xmr == c.BadWindow) panic("Tried to act on invalid window '{}'.", .{self.window_id});
        _ = c.XFlush(self.x_connection); // status irrelevant
        // z-value is not stored as part of 'XWindowAttributes'
    }

    /// Simple check to verify connection with XServer.
    /// * not guaranteed to catch all connection issues.
    pub fn statusConnection(self: *const Self) c_int {
        self.assertInitialized();
        _ = c.XSync(self.x_connection, 0); // try communicate, may reveal issues, status irrelevant
        return c.XConnectionNumber(self.x_connection); // return connection status
    }
};

test WindowHandler {
    var window = try WindowHandler.init(.{});
    defer window.deinit();

    try expectEqual(true, window.metaIsInitialized());
    try expectEqual(true, window.statusConnection() != 1);
    try expectEqual(false, window.metaIsOpen());

    window.open();

    //try expectEqual(true, window.metaIsOpen());

    std.time.sleep(5 * std.time.ns_per_s);
}
