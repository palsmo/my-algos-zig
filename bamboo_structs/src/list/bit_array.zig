//! Author: palsmo
//! Status: In Progress
//! About: Bit Array Data Structure
//! Read: https://en.wikipedia.org/wiki/Bit_array

const std = @import("std");

const maple = @import("maple_utils");

const mod_shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const ExecMode = mod_shared.ExecMode;
const IndexError = mod_shared.IndexError;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;
const fastMod = maple.math.fastMod;

/// A bit array implementation.
///
/// Properties:
/// Uses an 'Byte Array' with bit-masking under the hood.
///
///  complexity |     best     |   average    |    worst     |                factor
/// ------------|--------------|--------------|--------------|--------------------------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink
/// insertion   | O(1)         | O(1)         | O(n)         | grow
/// deletion    | O(1)         | O(1)         | O(n)         | shrink
/// lookup      | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|--------------------------------------
///  cache loc  | good         | good         | moderate     | usage pattern (scattered indexing)
/// ------------------------------------------------------------------------------------------------
pub fn BitArray(comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue
            init_capacity: usize = 32,
            // whether the queue can auto grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can auto shrink when grown past `init_capacity`,
            // size will half when used space falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        // struct fields
        buffer: []u8,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the array with the active `memory_mode` branch (read more _MemoryMode_).
        ///
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// .Alloc    | fn (allocator: Allocator, options: Options) !Self
        ///           | - Panics when 'options.init\_capacity' is zero or not a power of two.
        ///           |
        /// .Buffer   | fn (buf: []u8, options: Options) Self
        ///           | - Panics when 'buf.len' is zero or not a power of two.
        ///           | - The `options` *init_capacity*, *growable* and *shrinkable* are ignored.
        ///           |
        /// .Comptime | fn (comptime options: Options) Self
        ///           | - Panics when 'options.init\_capacity' is zero or not a power of two.
        /// ----------------------------------------------------------------------------------------
        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the array for using heap allocation.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) !Self {
            comptime assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});

            return .{
                .buffer = try allocator.alloc(u8, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the array for working with user provided `buf`.
        inline fn initBuffer(buf: []u8, comptime options: Options) Self {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});

            _ = options;

            return .{
                .buffer = buf,
                .options = .{
                    .init_capacity = 0, // * can't set `buf.len` since not always comptime, doesn't impact flow
                    .growable = false,
                    .shrinkable = false,
                },
                .allocator = null,
            };
        }

        /// Initialize the array for using comptime memory allocation.
        inline fn initComptime(comptime options: Options) Self {
            assertComptime(@src().fn_name);
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Alloc => {
                    assertAndMsg(self.allocator != null, "Passed allocator was unexpectedly 'null'.", .{});
                    self.allocator.?.free(self.buffer);
                },
                .Buffer, .Comptime => {
                    @compileError("Can't release array since it's not allocated on the heap (remove call 'deinit').");
                },
            }
        }

        /// Returns the byte index within array from `index`.
        pub inline fn calcByteIndex(index: usize) usize {
            return index / 8;
        }

        /// Returns the bit mask within byte from `index`.
        pub inline fn calcBitMask(index: usize) usize {
            if (index == 0 or index == 8) return 0x1;
            return @as(usize, 1) << fastMod(usize, index, 8);
        }

        /// Returns the bit index within byte from `index`.
        pub inline fn calcBitIndex(index: usize) usize {
            return fastMod(usize, index, 8);
        }

        /// Set bit `index` to boolean `value`.
        pub inline fn set(self: *Self, index: usize, value: bool) void {
            const byte_index = calcByteIndex(index);
            const bit_mask = calcBitMask(index);
            const bits = self.buffer[byte_index];
            self.buffer[byte_index] = (bits & ~bit_mask) | (value & bit_mask);
        }

        /// Set bit from `byte_index` with `bit_mask` to boolean `value`.
        pub inline fn setRaw(self: *Self, byte_index: usize, bit_mask: usize, value: bool) void {
            const bits = self.buffer[byte_index];
            self.buffer[byte_index] = (bits & ~bit_mask) | (value & bit_mask);
        }

        /// Toggle bit `index` between *true* <-> *false*.
        pub inline fn flip(self: *Self, index: usize) void {
            const byte_index = calcByteIndex(index);
            const bit_mask = calcBitMask(index);
            self.buffer[byte_index] ^= bit_mask;
        }

        // Toggle bit from `byte_index` with `bit_mask` between *true* <-> *false*.
        pub inline fn flipRaw(self: *Self, byte_index: usize, bit_mask: usize) void {
            self.buffer[byte_index] ^= bit_mask;
        }

        /// Get value of bit `index`.
        /// Issue key specs:
        /// - Throws error if 'index' is out of bounds of array (only *.Safe* `exec_mode`).
        pub inline fn get(self: *const Self, index: usize, comptime exec_mode: ExecMode) !u8 {
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (index < self.size) {} else return IndexError.OutOfBounds,
            }
            const byte_index = calcByteIndex(index);
            const bit_index = calcBitIndex(index);
            return (self.buffer[byte_index] >> bit_index) & 0x1;
        }

        /// Get value of bit from `byte_index` with `bit_index`.
        /// Issue key specs:
        /// - Throws error if 'index' is out of bounds of array (only *.Safe* `exec_mode`).
        pub inline fn getRaw(self: *const Self, byte_index: usize, bit_index: usize, comptime exec_mode: ExecMode) void {
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (byte_index < self.size) {} else return IndexError.OutOfBounds,
            }
            return (self.buffer[byte_index] >> bit_index) & 0x1;
        }
    };
}
