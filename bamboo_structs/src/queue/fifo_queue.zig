//! Author: palsmo
//! Read: https://en.wikipedia.org/wiki/FIFO_(computing_and_electronics)

const std = @import("std");

const _deque = @import("./double_ended_queue.zig");
const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const DoubleEndedQueue = _deque.DoubleEndedQueue;
const DoubleEndedQueueGeneric = _deque.DoubleEndedQueueGeneric;
const Error = shared.Error;

/// A first-in-first-out queue (fifo) implemented for items of type `T`.
/// Provides efficient insertion, removal and lookup operations.
///
/// Properties:
/// Uses 'DoubleEndedQueue' logic under the hood.
///
///  complexity |     best     |   average    |    worst     |        factor
/// ------------|--------------|--------------|--------------|----------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink routine
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink routine
/// insertion   | O(1)         | O(1)         | O(n)         | grow routine
/// deletion    | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup      | O(1)         | O(1)         | O(1)         | space saturation
/// ------------|--------------|--------------|--------------|----------------------
///  cache loc  | good         | good         | decent       | usage pattern (wrap)
/// --------------------------------------------------------------------------------
pub fn FifoQueue(comptime T: type) type {
    return struct {
        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 64,
            // whether the queue can grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of allocated
            shrinkable: bool = true,
        };

        /// Initialize the queue, allocating memory on the heap.
        /// User should release memory after use by calling 'deinit'.
        /// Function is valid only during _runtime_.
        pub fn initAlloc(options: Options, allocator: Allocator) !FifoQueueGeneric(T, .Alloc) {
            return .{
                .deque = try DoubleEndedQueue(T).initAlloc(.{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }, allocator),
            };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Fields in `options` that will be ignored are; init_capacity, growable, shrinkable.
        /// Function is valid during _comptime_ or _runtime_.
        pub fn initBuffer(buf: []T, options: Options) FifoQueueGeneric(T, .Buffer) {
            return .{
                .deque = DoubleEndedQueue(T).initBuffer(buf, .{
                    .init_capacity = buf.len,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Initialize the queue, allocating memory in .rodata or
        /// compiler's address space if not referenced runtime.
        /// Function is valid during _comptime_.
        pub fn initComptime(comptime options: Options) FifoQueueGeneric(T, .Comptime) {
            return .{
                .deque = DoubleEndedQueue(T).initComptime(.{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }
    };
}

/// Digest of some 'FifoQueue' init-function.
/// Depending on `buffer_type` certain operations may be pruned or optimized.
pub fn FifoQueueGeneric(comptime T: type, comptime buffer_type: enum { Alloc, Buffer, Comptime }) type {
    return struct {
        const Self = @This();

        // struct fields
        deque: switch (buffer_type) {
            .Alloc => DoubleEndedQueueGeneric(T, .Alloc),
            .Buffer => DoubleEndedQueueGeneric(T, .Buffer),
            .Comptime => DoubleEndedQueueGeneric(T, .Comptime),
        },

        /// Release allocated memory, cleanup routine for 'initAlloc'.
        pub fn deinit(self: *Self) void {
            self.deque.deinit();
        }

        /// Store an `item` first in the queue.
        /// This function throws error when adding at max capacity with 'self.options.growable' set to false.
        pub inline fn push(self: *Self, item: T) !void {
            return self.deque.push_last(item);
        }

        /// Get the first item in the queue, free its memory.
        /// This function throws error when trying to release from empty queue.
        pub inline fn pop(self: *Self) !T {
            return self.deque.pop_first();
        }

        /// Get the first item in the queue.
        /// Returns _null_ only if there's no value.
        pub inline fn peek(self: *Self) ?T {
            return self.deque.peek_first();
        }

        /// Get an item at index `index` in the queue.
        /// Returns _null_ only if there's no value.
        pub inline fn peekIndex(self: *Self, index: usize) ?T {
            return self.deque.peekIndex(index);
        }

        /// Get current amount of 'T' that's buffered in the queue.
        pub inline fn capacity(self: *Self) usize {
            return self.deque.capacity();
        }

        /// Get current amount of 'T' that's occupying the queue.
        pub inline fn length(self: *Self) usize {
            return self.deque.length();
        }

        /// Reset queue to its empty state.
        /// This function may throw error as part of the allocation process.
        pub inline fn reset(self: *Self) !void {
            return self.deque.reset();
        }

        /// Check if the queue is empty.
        /// Returns _true_ (empty) or _false_ (not empty).
        pub inline fn isEmpty(self: *Self) bool {
            return self.deque.isEmpty();
        }

        /// Check if the queue is full.
        /// Returns _true_ (full) or _false_ (not full).
        pub inline fn isFull(self: *Self) bool {
            return self.deque.isFull();
        }
    };
}

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Allocated FifoQueue" {
    const allocator = std.testing.allocator;
    var fifo = try FifoQueue(u8).initAlloc(.{
        .init_capacity = 4,
        .growable = true,
        .shrinkable = true,
    }, allocator);
    defer fifo.deinit();

    // test empty state -->

    try expectEqual(4, fifo.capacity());
    try expectEqual(0, fifo.length());
    try expectError(Error.Underflow, fifo.pop());
    try expectEqual(null, fifo.peek());
    try expectEqual(null, fifo.peekIndex(0));

    // test basic push and pop -->

    try fifo.push(1);
    try expectEqual(1, fifo.length());
    try expectEqual(1, try fifo.pop());
    try expectEqual(true, fifo.isEmpty());

    // test shrink -->

    fifo.deque.options.init_capacity = 8;
    try fifo.reset();
    fifo.deque.options.init_capacity = 2;

    try fifo.push(1);
    try fifo.push(2);
    try fifo.push(3);

    try expectEqual(8, fifo.capacity());
    _ = try fifo.pop(); // shrink trigger
    try expectEqual(4, fifo.capacity());

    // 2 3 x x

    try expectEqual(2, fifo.peekIndex(0));
    try expectEqual(3, fifo.peekIndex(1));
    try expectEqual(null, fifo.peekIndex(2));

    fifo.deque.options.init_capacity = 4;

    // test grow -->

    try fifo.push(4);
    try fifo.push(5);
    try expectEqual(true, fifo.isFull());

    try expectEqual(4, fifo.capacity());
    try fifo.push(6); // grow trigger
    try expectEqual(8, fifo.capacity());

    // 2 3 4 5 6 x x x

    try expectEqual(2, fifo.peekIndex(0));
    try expectEqual(3, fifo.peekIndex(1));
    try expectEqual(4, fifo.peekIndex(2));
    try expectEqual(5, fifo.peekIndex(3));
    try expectEqual(6, fifo.peekIndex(4));

    // test overflow error -->

    fifo.deque.options.growable = false;

    try fifo.push(7);
    try fifo.push(8);
    try fifo.push(9);

    try expectError(Error.Overflow, fifo.push(10));
}

test "Buffered FifoQueue" {
    var buffer: [2]u8 = undefined;
    var fifo = FifoQueue(u8).initBuffer(&buffer, .{});

    // test general -->

    try expectEqual(2, fifo.capacity());
    try expectEqual(0, fifo.length());
    try expectError(Error.Underflow, fifo.pop());
    try expectEqual(null, fifo.peek());
    try expectEqual(null, fifo.peekIndex(0));

    try fifo.push(1);
    try fifo.push(2);

    try expectEqual(2, fifo.length());
    try expectEqual(true, fifo.isFull());
    try expectEqual(Error.Overflow, fifo.push(3));

    try expectEqual(1, fifo.peek());
    try expectEqual(1, fifo.peekIndex(0));
    try expectEqual(2, fifo.peekIndex(1));

    try expectEqual(1, try fifo.pop());
    try expectEqual(2, try fifo.pop());

    try expectEqual(true, fifo.isEmpty());
}

test "Comptime FifoQueue" {
    comptime {
        var fifo = FifoQueue(u8).initComptime(.{
            .init_capacity = 2,
            .growable = false,
            .shrinkable = false,
        });

        // test general -->

        try expectEqual(2, fifo.capacity());
        try expectEqual(0, fifo.length());
        try expectError(Error.Underflow, fifo.pop());
        try expectEqual(null, fifo.peek());
        try expectEqual(null, fifo.peekIndex(0));

        try fifo.push(1);
        try fifo.push(2);

        try expectEqual(2, fifo.length());
        try expectEqual(true, fifo.isFull());
        try expectEqual(Error.Overflow, fifo.push(3));

        try expectEqual(1, fifo.peek());
        try expectEqual(1, fifo.peekIndex(0));
        try expectEqual(2, fifo.peekIndex(1));

        try expectEqual(1, try fifo.pop());
        try expectEqual(2, try fifo.pop());

        try expectEqual(true, fifo.isEmpty());
    }
}
