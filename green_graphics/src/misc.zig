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

    pub fn deinit(self: *WindowHandler) void {
        if (!self.is_initialized) return;
        if (self.window_id) |window_id| {
            _ = c.XDestroyWindow(self.x_connection, window_id); // ignore window_id
        }
        _ = c.XCloseDisplay(self.x_connection); // ignore display_id
        self.is_initialized = false;
    }

    const OptionsOpen = struct {
        // position within screen
        pos: struct { x: c_int, y: c_int } = .{ 0, 0 },
        // window dimension
        dim: struct { w: c_uint, h: c_uint } = .{ 800, 600 },
        border_width: c_uint = 0,
        border_color: ?c_ulong = null,
        backround_color: ?c_ulong = null,
        // * os may overwrite any of these
    };

    /// Open `self` window.
    pub fn open(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});

        const window_id = c.XCreateSimpleWindow(
            self.x_connection,
            self.window_parent_id,
            0, // x
            0, // y
            800, // width
            600, // height
            2, // width border
            c.XWhitePixel(self.x_connection, self.screen_id), // color border
            c.XBlackPixel(self.x_connection, self.screen_id), // color background
        );

        _ = c.XMapWindow(self.x_connection, window_id); // ignore window_id
        _ = c.XFlush(self.x_connection);

        self.window_id = window_id;
    }

    /// Close `self` window.
    pub fn close(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});

        const window_id = self.window_id orelse return;
        _ = c.XDestroyWindow(self.x_connection, window_id);
        _ = c.XFlush(self.x_connection);
    }

    /// Raise `self` to appear in front.
    pub fn raise(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});
        if (self.window_id) |window_id| {
            _ = c.XRaiseWindow(self.x_connection, window_id);
            _ = c.XFlush(self.x_connection);
        }
    }

    /// Raise `self` and windows with `self` as parent to appear in front.
    pub fn raiseAll(self: *Self) void {
        assertAndMsg(self.is_initialized, "WindowHandler hasn't been initialized (call 'init').", .{});
        if (self.window_id) |window_id| {
            _ = c.XMapRaised(self.x_connection, window_id);
            _ = c.XFlush(self.x_connection);
        }
    }

    /// Simple check to verify connection with XServer.
    /// * Not guaranteed to catch all connection issues.
    pub fn checkConnection(self: *const Self) bool {
        if (!self.is_initialized) return false;
        _ = c.XSync(self.x_connection, 0); // attempt to communicate with server, may reveal issues
        return c.XConnectionNumber(self.x_connection) != -1; // checks if connection still appears valid
    }
};

test WindowHandler {
    var window_handler = try WindowHandler.init(.{});
    defer window_handler.deinit();
    //try expectEqual(true, window_handler.checkConnection());
    //window_handler.deinit();
    //try expectEqual(false, window_handler.checkConnection());

    window_handler.open();

    // keep the window open for a few seconds
    std.time.sleep(10 * std.time.ns_per_s);
}
