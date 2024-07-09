const std = @import("std");

pub const Context = struct {
    eql: *const fn (comptime T: type, a: anytype, b: anytype) bool = std.mem.eql,
    hasher: *const fn (data: u32) u32 = std.hash.Murmur3_32.hashUint32,
};

pub fn StaticSet(comptime T: type) type {
    return struct {
        const Self = @This();

        set: []T,
        ctx: Context,

        // pub fn init(bytes: T, ctx: Context, allocator: std.mem.Allocator) Self {}

        pub fn initComptime(comptime size: usize, comptime ctx: Context) Self {
            if (!@inComptime()) @panic("Invalid at runtime.");
            return .{
                .set = blk: { // pointer to rodata
                    var set: [size]T = .{0} ** size;
                    break :blk &set;
                },
                .ctx = ctx,
            };
        }

        // pub fn insert() !void {}

        pub fn contains(self: *Self, value: T) bool {
            const value_h = @call(.always_inline, self.ctx.hasher, .{value});
            const i = value_h % self.set.len;
            const other = self.set[i];
            const other_h = @call(.always_inline, self.ctx.hasher, .{other});

            if (value_h == other_h) {
                // double check in case of collision
                return @call(.always_inline, self.ctx.eql, .{ value, other });
            }

            return false;
        }
    };
}

// testing -->

const expect = std.testing.expect;

test "empty set doesn't contain u32" {
    comptime {
        const size = 16;
        var set = StaticSet(u8).init_comptime(size, .{});

        const value: u32 = 4;
        const result = set.contains(value);

        expect(!result) catch unreachable;
    }
}

// I want this test to look like this and work, but `Context` lacks flexibility
//test "empty set doesn't contain u64" {
//    comptime {
//        const size = 16;
//        const hasher = std.hash.Fnv1a_64.hash;
//        var set = StaticSet(u8).init_comptime(size, .{ .hasher = hasher });
//
//        const value: u64 = 4;
//        const result = set.contains(value);
//
//        expect(!result) catch unreachable;
//    }
//}
