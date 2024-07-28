const std = @import("std");

const Allocator = std.mem.Allocator;

pub const KeyCode = enum(u8) {
    A = 65,
    B = 66,
    Escape = 27,
};

pub const KeySet = struct {
    const Self = @This();

    // struct fields
    keys: std.ArrayList(KeyCode),

    pub fn init(allocator: Allocator) Self {
        return .{
            .keys = std.ArrayList(KeyCode).init(allocator),
        };
    }

    pub fn deinit(self: *const KeySet) void {
        self.keys.deinit();
    }
};
