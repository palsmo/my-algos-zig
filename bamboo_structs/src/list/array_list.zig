//! Author: palsmo
//! Status: In Progress
//! About: Array List Data Structure
//! Read: https://en.wikipedia.org/wiki/Dynamic_array

const std = @import("std");

const maple = @import("maple_utils");

const shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const MemoryMode = shared.MemoryMode;
const assertAndMsg = maple.debug.assertAndMsg;
const assertComptime = maple.debug.assertComptime;
const assertPowOf2 = maple.math.assertPowOf2;
const panic = std.debug.panic;

/// An array list for items of type `T`.
/// Provides efficient ...
/// Useful ...
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
///
/// Reference to 'self.buffer' may become invalidated after grow/shrink routine,
/// use 'self.isValidRef' to verify.
///
/// Properties:
///
///  complexity |     best     |   average    |    worst     |        factor
/// ------------|--------------|--------------|--------------|----------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink routine
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink routine
/// insertion   | O(1)         | O(1)         | O(n)         | grow routine
/// deletion    | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup      | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|----------------------
///  cache loc  | good         | good         | good         | usage pattern (wrap)
/// --------------------------------------------------------------------------------
pub fn ArrayList(comptime T: type, comptime memory_mode: MemoryMode) type {
    struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the queue can grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        // struct fields
        buffer: []T,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the queue depending on `memory_mode` (read more _MemoryMode_ docs).
        /// Initialize the queue for using heap allocation.
        pub fn initAlloc(allocator: Allocator, options: Options) !Self {
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue for working with user provided `buf`.
        pub fn initBuffer(buf: []T, options: Options) Self {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(buf.len);

            _ = options;

            return .{
                .buffer = buf,
                .options = .{
                    .init_capacity = buf.len,
                    .growable = false,
                    .shrinkable = false,
                },
                .allocator = null,
            };
        }

        /// Initialize the queue for using comptime memory allocation.
        pub fn initComptime(comptime options: Options) Self {
            assertComptime(@src().fn_name);
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = b: { // * not 'free-after-use', compiler promotes
                    var buf: [options.init_capacity]T = undefined;
                    break :b &buf;
                },
                .options = options,
                .allocator = null,
            };
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Alloc => self.allocator.?.free(self.buffer),
                .Buffer, .Comptime => {
                    const msg = "The list is not allocated on the heap, remove unnecessary call 'deinit'";
                    if (@inComptime()) @compileError(msg) else panic(msg, .{});
                },
            }
        }
    };
}
