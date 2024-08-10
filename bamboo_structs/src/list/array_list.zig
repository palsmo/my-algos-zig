//! Author: palsmo
//! Status: In Progress
//! About: Array List Data Structure
//! Read: https://en.wikipedia.org/wiki/Dynamic_array

const std = @import("std");

const maple = @import("maple_utils");

const mod_shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const BufferError = mod_shared.BufferError;
const IndexError = mod_shared.IndexError;
const ExecMode = mod_shared.ExecMode;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;
const assertPowerOf2 = maple.assert.assertPowerOf2;
const panic = std.debug.panic;

/// An array list for items of type `T`.
/// Useful for storing sorted data due to the contiguous memory layout.
/// Worse for frequent insertions/deletions at the beginning (triggers whole copy).
///
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
/// Reference to 'self.buffer' may become invalid after grow/shrink routine, use 'self.isValidRef' to verify.
///
/// Properties:
/// Provides efficient handling of grouped items.
///
///  complexity |     best     |   average    |    worst     |                factor
/// ------------|--------------|--------------|--------------|--------------------------------------
/// insertion   | O(1)         | O(1)         | O(n)         | resize
/// deletion    | O(1)         | O(1)/O(n)    | O(n)/O(2n)   | fast_unorder/preserve_order, resize
/// lookup      | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|--------------------------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | resize
/// memory work | O(1)         | O(1)         | O(2)         | resize
/// ------------|--------------|--------------|--------------|--------------------------------------
///  cache loc  | good         | good         | good         | -
/// ------------------------------------------------------------------------------------------------
pub fn ArrayList(comptime T: type, comptime memory_mode: MemoryMode) type {
    struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the list, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the list can grow beyond `init_capacity`
            growable: bool = true,
            // whether the list can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        // struct fields
        buffer: []T,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the list with the active `memory_mode` branch (read more *MemoryMode*).
        ///
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// .Alloc    | fn (allocator: Allocator, comptime options: Options) !Self
        /// .Buffer   | fn (buf: []T, comptime options: Options) Self
        /// .Comptime | fn (comptime options: Options) Self
        /// ----------------------------------------------------------------------------------------
        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the list for using heap allocation.
        /// Issue key specs:
        /// - Panics when 'options.init\_capacity' is zero.
        /// - Throws error as part of an allocation process.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) !Self {
            comptime assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the list for working with user provided `buf`.
        /// Issue key specs:
        /// - Panics when 'buf.len' is zero.
        inline fn initBuffer(buf: []T, comptime options: Options) Self {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});

            _ = options;

            return .{
                .buffer = buf,
                .options = .{
                    .init_capacity = 0,
                    .growable = false,
                    .shrinkable = false,
                },
                .allocator = null,
            };
        }

        /// Initialize the list for using comptime memory allocation.
        /// Issue key specs:
        /// - Panics when 'options.init\_capacity' is zero.
        inline fn initComptime(comptime options: Options) Self {
            assertComptime(@src().fn_name);
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});

            return .{
                .buffer = b: { // * not free-after-use, compiler promotes
                    var buf: [options.init_capacity]T = undefined;
                    break :b &buf;
                },
                .options = options,
                .allocator = null,
            };
        }

        /// Release allocated memory, cleanup routine.
        /// Issue key specs:
        /// - Panic (only *.Buffer* and *.Comptime* `memory_mode`).
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Alloc => {
                    const ally = self.allocator orelse unreachable;
                    ally.free(self.buffer);
                },
                .Buffer, .Comptime => {
                    @compileError("Can't release, array is not allocated on the heap (remove call 'deinit').");
                },
            }
        }

        /// Get current amount of 'T' that's buffered in the list.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Get current amount of 'T' that's occupying the list.
        pub inline fn length(self: *const Self) usize {
            return self.size;
        }

        /// Check if the list is empty.
        pub inline fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// Check if the list is full.
        pub inline fn isFull(self: *const Self) bool {
            return self.size == &self.buffer.len;
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        pub inline fn isValidRef(self: *const Self, ptr: *const []T) bool {
            return ptr == &self.buffer;
        }

        /// Store an `item` last in the list.
        /// Issue key specs:
        /// - Throws error when adding at max capacity with 'self.options.growable' set to false.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        /// Other:
        /// - With *.Uncheck* `exec_mode` the user has manual control over the 'grow' routine.
        pub fn pushLast(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            // grow?
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => switch (self.size < self.buffer.len) {
                    true => {},
                    false => switch (memory_mode) {
                        .Buffer => return BufferError.Overflow,
                        .Alloc, .Comptime => if (self.options.growable) try self.grow() else {
                            return BufferError.Overflow;
                        },
                    },
                },
            }

            // add item and update size
            self.buffer[self.size] = item;
            self.size += 1;
        }

        /// Get an item at `index` from the list, free its memory.
        /// Issue key specs:
        /// - Throws error when trying to release from empty list.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        /// Other:
        /// - User ensure list size is not zero (only *.Uncheck* `exec_mode`).
        /// - User ensure list size is greater than `index` (only *.Uncheck* `exec_mode`).
        /// - User has manual control over the 'shrink' routine (only *.Uncheck* `exec_mode`).
        pub fn popIndex(
            self: *Self,
            index: usize,
            comptime mode: enum { PreserveOrder, FastUnorder },
            comptime exec_mode: ExecMode,
        ) !void {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            // check empty
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (self.size != 0) {} else return IndexError.OutOfBounds,
            }

            // check valid index
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (index < self.size) {} else return IndexError.OutOfBounds,
            }

            // perform delete strategy
            switch (mode) {
                .PreserveOrder => { // shift elements to fill gap
                    for (index..self.size - 1) |i| {
                        self.buffer[i] = self.buffer[i + 1];
                    }
                },
                .FastUnorder => { // swap with the last element
                    if (index < self.size - 1) {
                        self.buffer[index] = self.buffer[self.size - 1];
                    }
                },
            }

            self.size -= 1;

            // shrink?
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => switch (memory_mode) {
                    .Buffer => {},
                    .Alloc, .Comptime => switch (self.options.shrinkable) {
                        false => {},
                        true => {
                            const a = self.size >= self.options.init_capacity;
                            const b = self.size <= self.buffer.len / 4;
                            if (a and b) try self.shrink();
                        },
                    },
                },
            }
        }

        /// Load content of `buf` into list at `side`.
        /// Issue key specs:
        /// - Throws error when required capacity would overflow *usize*.
        /// - Throws error when list hasn't enough capacity (only *.Buffer* `memory_mode`).
        /// - Throws error when list hasn't enough capacity with 'self.options.growable' *false*.
        /// - Throws error when allocation process fail (only *.Alloc* `memory_mode`).
        pub fn stock(self: *Self, buf: []T, comptime side: enum { Before, After }) !void {
            _ = side;

            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            const required_capacity = try maple.math.safeAdd(usize, self.size, buf.len);

            // grow?
            if (required_capacity <= self.buffer.len) {
                switch (memory_mode) {
                    .Buffer => BufferError.NotEnoughSpace,
                    .Alloc, .Comptime => switch (self.options.growable) {
                        false => BufferError.NotEnoughSpace,
                        true => while (true) {
                            // TODO! This should be resize instead.
                            try self.grow();
                            if (required_capacity <= self.buffer.len) return;
                        },
                    },
                }
            }
        }

        /// Reset list to its empty initial state.
        /// Issue key specs:
        /// - Throws error when allocation process fail (only *.Alloc* `memory_mode`).
        pub fn reset(self: *Self) !void {
            switch (memory_mode) {
                .Buffer => {},
                .Alloc => {
                    if (self.buffer.len != self.options.init_capacity) {
                        // allocate new buffer with 'self.init_capacity'
                        const ally = self.allocator orelse unreachable;
                        ally.free(self.buffer);
                        self.buffer = try ally.alloc(T, self.options.init_capacity);
                    }
                },
                .Comptime => {
                    assertComptime(@src().fn_name);
                    if (self.buffer.len != self.options.init_capacity) {
                        // allocate new buffer with 'self.init_capacity'
                        // * not free-after-use, compiler promotes
                        var buf: [self.options.init_capacity]T = undefined;
                        self.buffer = &buf;
                    }
                },
            }

            self.size = 0;
        }

        /// Copy over current content into new buffer of **twice** the size.
        /// Issue key specs:
        /// - Throws error when new capacity would overflow *usize*.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn grow(self: *Self) !void {
            const new_capacity = try maple.math.safeMul(usize, self.buffer.len, 2);
            try self.resize(new_capacity);
        }

        /// Copy over current content into new buffer of **half** the size.
        /// Issue key specs:
        /// - Throws error when new capacity wouldn't fit all content in list.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn shrink(self: *Self) !void {
            const new_capacity = self.buffer.len / 2;
            try self.resize(new_capacity);
        }

        /// Copy over current content into new buffer of size `new_capacity`.
        /// Issue key specs:
        /// - Throws error when `new_capacity` wouldn't fit all content in list.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn resize(self: *Self, new_capacity: usize) !void {
            if (new_capacity < self.size) return BufferError.NotEnoughSpace;
            assertPowerOf2(new_capacity);

            const new_buffer = switch (memory_mode) {
                .Buffer => @compileError("Can't resize space of static buffer."),
                .Alloc => {
                    const ally = self.allocator orelse unreachable;
                    try ally.alloc(T, new_capacity);
                },
                .Comptime => b: { // * not free-after-use, compiler promotes
                    assertComptime(@src().fn_name);
                    var buf: [new_capacity]T = undefined;
                    break :b &buf;
                },
            };

            const old_mem = self.buffer[0 .. self.size - 1];
            const new_mem = new_buffer[0 .. self.size - 1];
            @memcpy(new_mem, old_mem);

            if (memory_mode == .Alloc) {
                const ally = self.allocator orelse unreachable;
                ally.free(self.buffer);
            }

            self.buffer = new_buffer;
        }
    };
}
