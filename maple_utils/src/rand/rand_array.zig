const std = @import("std");

const math = @import("../math/math.zig");

const Allocator = std.mem.Allocator;
const Random = std.Random;

/// Work with random arrays of type `T`.
/// `T` is asserted to be a runtime numeric type.
pub fn RandomArray(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Int, .Float => {},
        else => @compileError("Unsupported type for random data generation."),
    }

    return struct {
        const Self = @This();

        allocator: Allocator,

        /// Initialize for use.
        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Get a slice of random values of length `size` allocated on the heap.
        /// After use; ensure release of memory i.e. 'allocator.free(<slice>)'.
        pub fn get(size: usize, allocator: Allocator) ![]T {
            const slice = try allocator.alloc(T, size);
            errdefer allocator.free(slice);

            const bytes = if (T == u8) slice else std.mem.sliceAsBytes(slice);
            try std.posix.getrandom(bytes);

            return slice;
        }
    };
}

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test RandomArray {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    { // test for byte array
        const T = u8;
        const size = 100;
        const slice = try RandomArray(T).get(size, allocator);
        const info = @typeInfo(@TypeOf(slice));

        try expectEqual(size, slice.len);
        try expectEqual(T, info.Pointer.child);
    }

    { // test for less-type-byte array
        const T = u1;
        const size = 100;
        const slice = try RandomArray(T).get(size, allocator);
        const info = @typeInfo(@TypeOf(slice));

        try expectEqual(size, slice.len);
        try expectEqual(T, info.Pointer.child);
    }

    { // test for greater-type-byte array
        const T = u16;
        const size = 100;
        const slice = try RandomArray(T).get(size, allocator);
        const info = @typeInfo(@TypeOf(slice));

        try expectEqual(size, slice.len);
        try expectEqual(T, info.Pointer.child);
    }

    { // test randomness/entropy
        const T = u8;
        const size = 100;
        const sample_size: u8 = 10;

        var ent: f64 = 0.0;
        var i = sample_size;
        while (i > 0) : (i -= 1) {
            const array = try RandomArray(T).get(size, allocator);
            ent += try math.entropy(array, allocator);
        }

        const average = ent / sample_size;
        const ent_max = @log2(@as(f64, @floatFromInt(size)));
        const threshold = 0.9 * ent_max; // 90% of max entropy

        try expect(average >= threshold);
    }
}
