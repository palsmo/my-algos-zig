const std = @import("std");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub fn Context(comptime T: type, comptime H: type) type {
    const T_info = @typeInfo(T);
    assert(T_info.Int);
    assert(T_info.Int.signedness == .unsigned);
    return struct {
        const Self = @This();

        eql: ?fn (a: T, b: T) bool,
        hash: fn (v: T) H,

        pub fn default() Self {
            const bits = T_info.Int.bits;
            var self = Self{};
            switch (bits) {
                32 => self.hash = std.hash.Murmur3_32.hash,
                64 => self.hash = std.hash.Murmur2_64.hash,
                else => @compileLog("Couldn't esablish default for hash digest type", H),
            }
            switch (T_info) {
                .Pointer => switch (T_info.Pointer.size) {
                    .Many, .Slice => self.eql = std.mem.eql,
                },
                .Array => self.eql = std.mem.eql,
            }
        }
    };
}

//std.HashMap

/// The size of the set is fixed, allocated when calling the init-function.
/// `T` is the type to store, `H` is the type of hash digest, `ctx` contains
/// the hasher `hash` as well as `eql` which decides equality between two
/// inputs of type `T`.
pub fn StaticSet(comptime T: type, comptime H: type) type {
    return struct {
        const Self = @This();

        set: []T,
        ctx: Context(T, H),
        allocator: ?Allocator = null,

        //pub fn init(bytes: T, allocator: Allocator) void {
        //    return .{
        //        .set = try allocator.alloc(u8, bytes),
        //        .allocator = allocator,
        //    };
        //}

        pub fn initComptime(comptime bytes: T, comptime ctx: Context) Self {
            if (!@inComptime()) @panic("Invalid at runtime.");
            return .{
                .set = blk: { // pointer to rodata
                    var set: [bytes]T = undefined;
                    break :blk &set;
                },
                .ctx = ctx,
                .allocator = null,
            };
        }

        pub fn insert() void {}

        pub fn contains(self: *Self, value: T) T {
            const value_h = switch (self.mode) {
                .type_32 => self.mode.type_32.hash(value),
                .type_64 => self.mode.type_64.hash(value),
            };
            const i = value_h % self.set.len;
            const _value = self.set[i];
            if (value_h == self.ctx.hash(_value)) {
                const result = @call(.always_inline, self.ctx.hash, .{ _value, value });
                if (result) return false;
            }
            return true;
        }
    };
}

// testing -->

const expectEqual = std.testing.expectEqual;

test "empty set doesn't contain value" {
    comptime {
        var set = StaticSet(u8, u32).init_comptime(4, .{}.default());
        const value = 4;
        const result = set.contains(value);
        try expectEqual(false, result);
    }
}
