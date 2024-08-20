//! Author: palsmo
//! Status: In Progress
//! About: Linux Input Subsystem Handler

const std = @import("std");
const linux = std.os.linux;

const root_shared = @import("./shared.zig");

const InputError = root_shared.InputError;
const panic = std.debug.panic;

// Linux input handler.
pub const InputHandler = struct {
    const Self = @This();

    pub const Event = packed struct(u24) {
        code: u16,
    };

    // struct fields
    file_descriptor: linux.fd_t,

    pub fn init(device_path: [*:0]const u8) !Self {
        // open device in read-only and non-blocking mode
        const flags: linux.O = .{ .ACCMODE = .RDONLY, .NONBLOCK = true };
        const rc = linux.open(device_path, flags, 0);

        var fd: linux.fd_t = undefined;

        switch (linux.E.init(rc)) {
            .SUCCESS => fd = @intCast(rc),
            .ACCES => return InputError.PermissionDenied,
            .NOENT => return InputError.DeviceNotFound,
            .BUSY => return InputError.DeviceBusy,
            else => |ec| {
                std.log.err("Probed access to device '{s}', unknown error '{}'", .{ device_path, ec });
                return InputError.Undefined;
            },
        }

        std.log.info("Probed access to device '{s}', no errors.\n", .{device_path});
        return .{ .file_descriptor = fd };
    }

    pub fn deinit(self: *Self) void {
        linux.close(self.file_descriptor);
    }

    pub fn readEvent(self: *Self) !void {
        //const event: Event = undefined;
        var buf: u64 = 0;
        const rc = linux.read(self.file_descriptor, std.mem.asBytes(&buf), @sizeOf(@TypeOf(buf)));

        switch (linux.E.init(rc)) {
            .SUCCESS => {},
            else => return InputError.Undefined,
        }

        std.debug.print("{}\n", .{buf});
    }
};

test InputHandler {
    const device_path = "/dev/input/event18";
    var input_handler = try InputHandler.init(device_path);
    while (true) {
        try input_handler.readEvent();
        std.time.sleep(10 * std.time.ns_per_ms);
    }
}
