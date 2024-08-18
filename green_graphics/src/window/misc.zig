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

pub const WindowHandler = struct {
    const Self = @This();

    pub const Options = struct {
        // hostname:number.screen_number, 'null' = value of DISPLAY env_var
        display_spec: [*c]const u8 = null,
        // parent window, 'null' = root window
        window_parent_id: ?c.Window = null,
    };

    // struct fields
    x_connection: *c.Display,
    screen_id: c_int,
    window_parent_id: c.Window,
    window_id: ?c.Window,

    is_initialized: bool = false,

    /// Initialize the handler by connecting to Xserver.
    /// Issue key specs:
    /// - Throws error when connection process fail.
    pub fn init(options: Options) !Self {
        const x_connection = c.XOpenDisplay(options.display_spec) orelse {
            return XClientError.FailedToEstablishConnectionWithServer;
        };
        const screen_id = c.XDefaultScreen(x_connection);
        const window_parent_id = options.window_parent_id orelse c.XRootWindow(x_connection, screen_id);

        return .{
            .x_connection = x_connection,
            .screen_id = screen_id,
            .window_parent_id = window_parent_id,
            .window_id = null,
            .is_initialized = true,
        };
    }

    /// Issue key specs:
    /// - Panic when `self.window_id` isn't a defined *c.Window*.
    pub fn deinit(self: *WindowHandler) void {
        if (!self.is_initialized) return;

        const window_id = self.window_id orelse panic("Tried to destroy invalid window 'null'.", .{});
        const status_xdw = c.XDestroyWindow(self.x_connection, window_id);
        if (status_xdw == c.BadWindow) panic("Tried to destroy invalid window '{}'.", .{window_id});
        _ = c.XCloseDisplay(self.x_connection); // status irrelevant

        self.is_initialized = false;
    }

    /// Assert that `self` has called 'init'.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub inline fn assertInitialized(self: *const Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});
    }

    /// Assert that 'self.window_id' isn't *null*.
    pub inline fn assertHasWindow(self: *const Self) void {
        assertAndMsg(self.window_id != null, "Can't act on undefined 'self.window_id'.", .{}); // TODO
    }

    /// Set the x-coordinate position.
    pub fn setX(self: *Self, px: c_int) void {
        self.assertHasWindow();
        c.XMoveWindow(self.x_connection, window_id, x, y);
    }

    /// Get the x-coordinate position.
    pub fn getX(self: *Self) c_int {
        self.assertHasWindow();
        const window_id = self.window_id orelse panic("Tried to read attribute of invalid window 'null'.", .{});
        const attrs: c.XWindowAttributes = undefined;
        const status_xgwa = c.XGetWindowAttributes(self.x_connection, window_id, &attrs);
        if (status_xgwa != c.BadWindow) panic("Tried to read attribute of invalid window '{}'.", .{window_id});
    }

    pub const OptionsOpenSimple = struct {
        // position within screen
        pos: struct { x: c_int, y: c_int } = .{ .x = 0, .y = 0 },
        // window dimensions
        dim: struct { w: c_uint, h: c_uint } = .{ .w = 800, .h = 600 },
        border_width: c_uint = 0,
        border_color: ?c_ulong = null,
        backround_color: ?c_ulong = null,
        // * os may overwrite any of these
    };

    /// Open simple `self` window.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    pub fn openSimple(self: *Self, options: OptionsOpenSimple) void {
        const window_id = c.XCreateSimpleWindow(
            self.x_connection,
            self.window_parent_id,
            options.pos.x,
            options.pos.y,
            options.dim.w,
            options.dim.h,
            options.border_width,
            options.border_color orelse c.XWhitePixel(self.x_connection, self.screen_id),
            options.backround_color orelse c.XBlackPixel(self.x_connection, self.screen_id),
        );

        _ = c.XMapWindow(self.x_connection, window_id); // status irrelevant
        _ = c.XFlush(self.x_connection); // send requests immediately, status irrelevant

        self.window_id = window_id;
    }

    pub const OptionsOpenDetailed = struct {
        // window title, 'null' = no title
        title: [*c]const u8 = null,
        // position within screen
        pos: struct { x: c_int, y: c_int } = .{ .x = 0, .y = 0 },
        // window dimensions
        dim: struct { w: c_uint, h: c_uint } = .{ .w = 800, .h = 600 },
        border_width: c_uint = 0,
        depth: c_int = c.CopyFromParent,
        class: c_uint = c.InputOutput,
        visual: ?*c.Visual = null,
        valuemask: c_ulong = c.CWBackPixel | c.CWBorderPixel | c.CWEventMask,
        attributes: ?c.XSetWindowAttributes = null,
    };

    /// Open detailed `self` window.
    pub fn openDetailed(self: *Self, options: OptionsOpenDetailed) void {
        const window_id = c.XCreateWindow(
            self.x_connection,
            self.window_parent_id,
            options.pos.x,
            options.pos.y,
            options.dim.w,
            options.dim.h,
            options.border_width,
            options.depth,
            options.class,
            options.visual,
            options.valuemask,
            options.attributes,
        );

        _ = c.XStoreName(self.x_connection, window_id, options.title); // status irrelevant
        _ = c.XMapWindow(self.x_connection, window_id); // status irrelevant
        _ = c.XFlush(self.x_connection);

        self.window_id = window_id;
    }

    /// Close `self` window.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self.window_id` isn't a defined *c.Window*.
    pub fn close(self: *Self) void {
        const window_id = self.window_id orelse panic("Tried to destroy invalid window 'null'.", .{});

        const status_xdw = c.XDestroyWindow(self.x_connection, window_id);
        if (status_xdw == c.BadWindow) panic("Tried to destroy invalid window '{}'.", .{window_id});
        _ = c.XFlush(self.x_connection); // send requests immediately, status irrelevant

        self.window_id = null;
    }

    /// Raise `self` to appear in front.
    /// Issue key specs:
    /// - Panic when `self` hasn't been initialized.
    /// - Panic when `self.window_id` isn't a defined *c.Window*.
    pub fn raise(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});

        const window_id = self.window_id orelse panic("Tried to raise invalid window 'null'.", .{});
        const status_xrw = c.XRaiseWindow(self.x_connection, window_id);
        if (status_xrw != c.BadWindow) panic("Tried to raise invalid window '{}'.", .{window_id});
        _ = c.XFlush(self.x_connection); // send requests immediately, status irrelevant
    }

    /// Raise `self` and windows with `self` as parent to appear in front.
    /// Issue key specs:
    /// - Panic when `self` han't been initialized.
    /// - Panic when `self.window_id` isn't a defined *c.Window*.
    pub fn raiseAll(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});

        const window_id = self.window_id orelse panic("Tried to raise invalid window 'null'.", .{});
        const status_xmr = c.XMapRaised(self.x_connection, window_id);
        if (status_xmr != c.BadWindow) panic("Tried to raise invalid window '{}'.", .{window_id});
        _ = c.XFlush(self.x_connection); // send requests immediately, status irrelevant
    }

    /// Simple check to verify connection with XServer.
    /// * not guaranteed to catch all connection issues.
    pub fn checkConnection(self: *const Self) bool {
        if (!self.is_initialized) return false;
        _ = c.XSync(self.x_connection, 0); // communicate with server, may reveal issues, status irrelevant
        return c.XConnectionNumber(self.x_connection) != -1; // checks if connection still appears valid
    }
};

test WindowHandler {
    var window_handler = try WindowHandler.init(.{});
    defer window_handler.deinit();

    window_handler.assertInitialized();
    window_handler.openDetailed(.{ .title = "My Detailed Window" });

    // keep the window open for a few seconds
    std.time.sleep(10 * std.time.ns_per_s);

    //try expectEqual(true, window_handler.checkConnection());
    //window_handler.deinit();
    //try expectEqual(false, window_handler.checkConnection());
}
