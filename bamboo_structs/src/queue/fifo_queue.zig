//! Author: palsmo
//! Status: Done
//! About: First-In-First-Out Queue Data Structure
//! Read: https://en.wikipedia.org/wiki/FIFO_(computing_and_electronics)

const std = @import("std");

const maple = @import("maple.utils");

const mod_shared = @import("../shared.zig");
const root_deque = @import("./double_ended_queue.zig");

const Allocator = std.mem.Allocator;
const DoubleEndedQueue = root_deque.DoubleEndedQueue;
const DoubleEndedQueueGeneric = root_deque.DoubleEndedQueueGeneric;
const BufferError = mod_shared.BufferError;
const ExecMode = mod_shared.ExecMode;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.debug.assertAndMsg;
const assertPowOf2 = maple.math.assertPowOf2;

/// A first-in-first-out queue for items of type `T`.
/// Provides efficient handling of queuing data.
/// Shouldn't be used to store sorted items (has potentially non-contiguous memory layout).
/// Can be useful as event/task queue, message buffer or primitive for other structures.
///
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
/// Reference to 'self.deque.buffer' may become invalidated after grow/shrink routine,
/// use 'self.isValidRef' to verify.
///
/// Properties:
/// Relies on 'DoubleEndedQueue' structure under the hood.
///
///  complexity |     best     |   average    |    worst     |                factor
/// ------------|--------------|--------------|--------------|--------------------------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink
/// insertion   | O(1)         | O(1)         | O(n)         | grow
/// deletion    | O(1)         | O(1)         | O(n)         | shrink
/// lookup      | O(1)         | O(1)         | O(1)         | space saturation
/// ------------|--------------|--------------|--------------|--------------------------------------
///  cache loc  | good         | good         | moderate     | usage pattern (wrap)
/// ------------------------------------------------------------------------------------------------
pub fn FifoQueue(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the queue can auto grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can auto shrink when grown past `init_capacity`,
            // size will half when used space falls below 1/4 of allocated
            shrinkable: bool = true,
        };

        // struct fields
        deque: switch (memory_mode) {
            .Alloc => DoubleEndedQueue(T, .Alloc),
            .Buffer => DoubleEndedQueue(T, .Buffer),
            .Comptime => DoubleEndedQueue(T, .Comptime),
        },

        /// Initialize the queue with the active `memory_mode` branch (read more _MemoryMode_).
        ///
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// .Alloc    | fn (allocator: Allocator, options: Options) !Self
        ///           | - Panics when 'options.init\_capacity' is zero or not a power of two.
        ///           |
        /// .Buffer   | fn (buf: []T, options: Options) Self
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

        /// Initialize the queue for using heap allocation.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) !Self {
            return .{
                .deque = try DoubleEndedQueue(T, .Alloc).init(allocator, .{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Initialize the queue for working with user provided `buf`.
        inline fn initBuffer(buf: []T, comptime options: Options) Self {
            return .{
                .deque = DoubleEndedQueue(T, .Buffer).init(buf, .{
                    .init_capacity = 0,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Initialize the queue for using comptime memory allocation.
        inline fn initComptime(comptime options: Options) Self {
            return .{
                .deque = DoubleEndedQueue(T, .Comptime).init(.{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *const Self) void {
            return @call(.always_inline, @TypeOf(self.deque).deinit, .{&self.deque});
        }

        /// Identical to 'push' but guaranteed to be inlined.
        pub inline fn pushInline(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            return @call(.always_inline, @TypeOf(self.deque).pushLastInline, .{ &self.deque, item, exec_mode });
        }

        /// Store an `item` last in the queue.
        /// Issue key specs:
        /// - Throws error when adding at max capacity with 'self.options.growable' set to false.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        /// Other:
        /// - With *.Uncheck* `exec_mode` the user has manual control over the 'grow' routine.
        pub fn push(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            return @call(.always_inline, @TypeOf(self.deque).pushLast, .{ &self.deque, item, exec_mode });
        }

        /// Store all `items` last in the queue.
        /// Issue key specs:
        /// - Throws error when required capacity would overflow *usize*.
        /// - Throws error when queue hasn't enough capacity (only *.Buffer* `memory_mode`).
        /// - Throws error when queue hasn't enough capacity with 'self.options.growable' set to false.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn pushBatch(self: *Self, items: []const T) !void {
            return @call(.always_inline, @TypeOf(self.deque).pushLastBatch, .{ &self.deque, items });
        }

        /// Identical to 'pop' but guaranteed to be inlined.
        pub inline fn popInline(self: *Self, comptime exec_mode: ExecMode) !T {
            return @call(.always_inline, @TypeOf(self.deque).popFirstInline, .{ &self.deque, exec_mode });
        }
        /// Get the first item in the queue, free its memory.
        /// Issue key specs:
        /// - Throws error when trying to release from empty queue.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        /// Other:
        /// - With *.Uncheck* `exec_mode` the user has manual control over the 'shrink' routine.
        pub fn pop(self: *Self, comptime exec_mode: ExecMode) !T {
            return @call(.always_inline, @TypeOf(self.deque).popFirst, .{ &self.deque, exec_mode });
        }

        /// Identical to 'peek' but guaranteed to be inlined.
        pub inline fn peekInline(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, @TypeOf(self.deque).peekFirstInline, .{ &self.deque, exec_mode });
        }

        /// Get the first item in the queue.
        /// Issue key specs:
        /// - Returns *null* only if queue is empty.
        pub fn peek(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, @TypeOf(self.deque).peekFirst, .{ &self.deque, exec_mode });
        }

        /// Identical to 'peekIndex' but guaranteed to be inlined.
        pub inline fn peekIndexInline(self: *const Self, index: usize, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, @TypeOf(self.deque).peekIndexInline, .{ &self.deque, index, exec_mode });
        }

        /// Get an item at index `index` in the queue.
        /// Issue key specs:
        /// - Returns *null* if `index` is out of bounds for 'self.length()' (only *.Safe* `exec_mode`).
        pub fn peekIndex(self: *const Self, index: usize, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, @TypeOf(self.deque).peekIndex, .{ &self.deque, index, exec_mode });
        }

        /// Get current amount of 'T' that's buffered in the queue.
        pub inline fn capacity(self: *const Self) usize {
            return @call(.always_inline, @TypeOf(self.deque).capacity, .{&self.deque});
        }

        /// Get current amount of 'T' that's occupying the queue.
        pub inline fn length(self: *const Self) usize {
            return @call(.always_inline, @TypeOf(self.deque).length, .{&self.deque});
        }

        /// Check if the queue is empty.
        /// Returns _true_ (empty) or _false_ (not empty).
        pub inline fn isEmpty(self: *const Self) bool {
            return @call(.always_inline, @TypeOf(self.deque).isEmpty, .{&self.deque});
        }

        /// Check if the queue is full.
        /// Returns _true_ (full) or _false_ (not full).
        pub inline fn isFull(self: *const Self) bool {
            return @call(.always_inline, @TypeOf(self.deque).isFull, .{&self.deque});
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        pub inline fn isValidRef(self: *const Self, ptr: *const []T) bool {
            return ptr == &self.buffer;
        }
        /// Reset queue to its empty state.
        /// Issue key specs:
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub inline fn reset(self: *Self) !void {
            return @call(.always_inline, @TypeOf(self.deque).reset, .{&self.deque});
        }

        /// Copy over current content into new buffer of **twice** the size.
        /// Issue key specs:
        /// - Panics when 'self.allocator' is *null*.
        /// - Throws error when new capacity would overflow *usize*.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn grow(self: *Self) !void {
            return @call(.always_inline, @TypeOf(self.deque).grow, .{&self.deque});
        }

        /// Copy over current content into new buffer of **half** the size.
        /// Issue key specs:
        /// - Panics when 'self.allocator' is *null*.
        /// - Throws error when new capacity wouldn't fit all content in queue.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn shrink(self: *Self) !void {
            return @call(.always_inline, @TypeOf(self.deque).shrink, .{&self.deque});
        }

        /// Copy over current content into new buffer of size `new_capacity`.
        /// Issue key specs:
        /// - Panics when 'self.allocator' is *null*.
        /// - Throws error when `new_capacity` wouldn't fit all content in queue.
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn resize(self: *Self) !void {
            return @call(.always_inline, @TypeOf(self.deque).resize, .{&self.deque});
        }
    };
}

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Comptime FifoQueue" {
    comptime {
        const T_fifo = FifoQueue(u8, .Comptime);
        var fifo: T_fifo = T_fifo.init(.{
            .init_capacity = 4,
            .growable = true,
            .shrinkable = true,
        });

        // test empty state -->

        try expectEqual(4, fifo.capacity());
        try expectEqual(0, fifo.length());
        try expectError(BufferError.Underflow, fifo.pop(.Safe));
        try expectEqual(null, fifo.peek(.Safe));
        try expectEqual(null, fifo.peekIndex(0, .Safe));

        // test basic push and pop -->

        try fifo.push(1, .Safe);
        try expectEqual(1, fifo.length());
        try expectEqual(1, fifo.pop(.Safe));
        try expectEqual(true, fifo.isEmpty());

        // test shrink -->

        fifo.deque.options.init_capacity = 8;
        try fifo.reset();
        fifo.deque.options.init_capacity = 2;

        try fifo.push(1, .Safe);
        try fifo.push(2, .Safe);
        try fifo.push(3, .Safe);

        try expectEqual(8, fifo.capacity());
        _ = try fifo.pop(.Safe); // shrink trigger
        try expectEqual(4, fifo.capacity());

        // 2 3 x x

        try expectEqual(2, fifo.peekIndex(0, .Safe));
        try expectEqual(3, fifo.peekIndex(1, .Safe));
        try expectEqual(null, fifo.peekIndex(2, .Safe));

        fifo.deque.options.init_capacity = 4;

        // test grow -->

        try fifo.push(4, .Safe);
        try fifo.push(5, .Safe);
        try expectEqual(true, fifo.isFull());

        try expectEqual(4, fifo.capacity());
        try fifo.push(6, .Safe); // grow trigger
        try expectEqual(8, fifo.capacity());

        // 2 3 4 5 6 x x x

        try expectEqual(2, fifo.peekIndex(0, .Safe));
        try expectEqual(3, fifo.peekIndex(1, .Safe));
        try expectEqual(4, fifo.peekIndex(2, .Safe));
        try expectEqual(5, fifo.peekIndex(3, .Safe));
        try expectEqual(6, fifo.peekIndex(4, .Safe));

        // test overflow error -->

        fifo.deque.options.growable = false;

        try fifo.push(7, .Safe);
        try fifo.push(8, .Safe);
        try fifo.push(9, .Safe);

        try expectError(BufferError.Overflow, fifo.push(10, .Safe));
    }
}

test "Buffered FifoQueue" {
    var buffer: [2]u8 = undefined;
    const T_fifo = FifoQueue(u8, .Buffer);
    var fifo: T_fifo = T_fifo.init(&buffer, .{});

    // test general -->

    try expectEqual(2, fifo.capacity());
    try expectEqual(0, fifo.length());
    try expectError(BufferError.Underflow, fifo.pop(.Safe));
    try expectEqual(null, fifo.peek(.Safe));
    try expectEqual(null, fifo.peekIndex(0, .Safe));

    try fifo.push(1, .Safe);
    try fifo.push(2, .Safe);

    try expectEqual(2, fifo.length());
    try expectEqual(true, fifo.isFull());
    try expectEqual(BufferError.Overflow, fifo.push(3, .Safe));

    try expectEqual(1, fifo.peek(.Safe));
    try expectEqual(1, fifo.peekIndex(0, .Safe));
    try expectEqual(2, fifo.peekIndex(1, .Safe));

    try expectEqual(1, fifo.pop(.Safe));
    try expectEqual(2, fifo.pop(.Safe));

    try expectEqual(true, fifo.isEmpty());
}

test "Allocated FifoQueue" {
    const allocator = std.testing.allocator;
    const T_fifo = FifoQueue(u8, .Alloc);
    var fifo: T_fifo = try T_fifo.init(allocator, .{
        .init_capacity = 2,
        .growable = false,
        .shrinkable = false,
    });

    defer fifo.deinit();

    // test general -->

    try expectEqual(2, fifo.capacity());
    try expectEqual(0, fifo.length());
    try expectError(BufferError.Underflow, fifo.pop(.Safe));
    try expectEqual(null, fifo.peek(.Safe));
    try expectEqual(null, fifo.peekIndex(0, .Safe));

    try fifo.push(1, .Safe);
    try fifo.push(2, .Safe);

    try expectEqual(2, fifo.length());
    try expectEqual(true, fifo.isFull());
    try expectEqual(BufferError.Overflow, fifo.push(3, .Safe));

    try expectEqual(1, fifo.peek(.Safe));
    try expectEqual(1, fifo.peekIndex(0, .Safe));
    try expectEqual(2, fifo.peekIndex(1, .Safe));

    try expectEqual(1, fifo.pop(.Safe));
    try expectEqual(2, fifo.pop(.Safe));

    try expectEqual(true, fifo.isEmpty());
}
