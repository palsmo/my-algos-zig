const std = @import("std");

const Allocator = std.mem.Allocator;
const Random = std.Random;
const panic = std.debug.panic;

/// Get a slice of random values of length `size`, allocated on the heap.
/// Can be used for cryptographic purposes.
pub fn getSlice(comptime T: type, size: usize, allocator: Allocator) ![]T {
    const slice = try allocator.alloc(T, size);
    errdefer allocator.free(slice);

    const bytes = if (T == u8) slice else std.mem.sliceAsBytes(slice);
    try std.posix.getrandom(bytes);

    return slice;
}

//pub fn getSliceRuntime(comptime T: type, size: usize) []T {
//}
//
///// Get a slice of random values of length `size`, allocated in read-only data.
//pub fn getSliceComptime(comtpime T: type, size: usize) []T {
//    const slice = blk: {
//        var buf: [size]T = undefined;
//        break :blk &buf; // pointer to ro-data
//    };
//}
