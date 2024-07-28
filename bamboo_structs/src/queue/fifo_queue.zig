//! Author: palsmo
//! Status: Done
//! Read: https://en.wikipedia.org/wiki/FIFO_(computing_and_electronics)
//! About: First-In-First-Out Queue Data Structure

const std = @import("std");

const root_deque = @import("./double_ended_queue.zig");
const root_shared = @import("./shared.zig");
const shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const DoubleEndedQueue = root_deque.DoubleEndedQueue;
const DoubleEndedQueueGeneric = root_deque.DoubleEndedQueueGeneric;
const Error = root_shared.Error;
const MemoryMode = shared.MemoryMode;

/// A first-in-first-out queue (fifo) implemented for items of type `T`.
/// Provides efficient insertion, removal and lookup operations.
/// Useful as event/task queue, message buffer or primitive for other structures.
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
///
/// Properties:
/// Uses 'DoubleEndedQueue' structure under the hood.
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
pub fn FifoQueue(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the queue can grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of allocated
            shrinkable: bool = true,
        };

        // struct fields
        deque: switch (memory_mode) {
            .Alloc => DoubleEndedQueue(T, .Alloc),
            .Buffer => DoubleEndedQueue(T, .Buffer),
            .Comptime => DoubleEndedQueue(T, .Comptime),
        },

        /// Initialize the queue depending on `memory_mode` (read more _MemoryMode_ docs).
        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the queue for using heap allocation.
        fn initAlloc(allocator: Allocator, options: Options) !Self {
            return .{
                .deque = try DoubleEndedQueue(T, .Alloc).init(allocator, .{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Initialize the queue for working with user provided `buf`.
        fn initBuffer(buf: []T, options: Options) Self {
            return .{
                .deque = DoubleEndedQueue(T, .Buffer).init(buf, .{
                    .init_capacity = buf.len,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Initialize the queue for using comptime memory allocation.
        fn initComptime(comptime options: Options) Self {
            return .{
                .deque = DoubleEndedQueue(T, .Comptime).init(.{
                    .init_capacity = options.init_capacity,
                    .growable = options.growable,
                    .shrinkable = options.shrinkable,
                }),
            };
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *Self) void {
            self.deque.deinit();
        }

        /// Identical to 'push' but guaranteed to be inlined.
        pub inline fn pushInline(self: *Self, item: T) !void {
            try self.deque.pushLastInline(self, item);
        }

        /// Store an `item` first in the queue.
        /// This function throws error when adding at max capacity with 'self.options.growable' set to false.
        pub inline fn push(self: *Self, item: T) !void {
            try self.deque.pushLast(item);
        }

        /// Identical to 'pop' but guaranteed to be inlined.
        pub inline fn popInline(self: *Self) !T {
            return try self.deque.popFirstInline(self);
        }

        /// Get the first item in the queue, free its memory.
        /// This function throws error when trying to release from empty queue.
        pub inline fn pop(self: *Self) !T {
            return try self.deque.popFirst();
        }

        /// Identical to 'peek' but guaranteed to be inlined.
        pub inline fn peekInline(self: *const Self) ?T {
            return self.deque.peekFirstInline();
        }

        /// Get the first item in the queue.
        /// Returns _null_ only if there's no value.
        pub inline fn peek(self: *const Self) ?T {
            return self.deque.peekFirst();
        }

        /// Identical to 'peekIndex' but guaranteed to be inlined.
        pub inline fn peekIndexInline(self: *const Self, index: usize) ?T {
            return self.deque.peekIndexInline(self, index);
        }

        /// Get an item at index `index` in the queue.
        /// Returns _null_ only if there's no value.
        pub inline fn peekIndex(self: *const Self, index: usize) ?T {
            return self.deque.peekIndex(index);
        }

        /// Get current amount of 'T' that's buffered in the queue.
        pub inline fn capacity(self: *const Self) usize {
            return self.deque.capacity();
        }

        /// Get current amount of 'T' that's occupying the queue.
        pub inline fn length(self: *const Self) usize {
            return self.deque.length();
        }

        /// Reset queue to its empty state.
        /// This function may throw error as part of an allocation process.
        pub inline fn reset(self: *Self) !void {
            try self.deque.reset();
        }

        /// Check if the queue is empty.
        /// Returns _true_ (empty) or _false_ (not empty).
        pub inline fn isEmpty(self: *const Self) bool {
            return self.deque.isEmpty();
        }

        /// Check if the queue is full.
        /// Returns _true_ (full) or _false_ (not full).
        pub inline fn isFull(self: *const Self) bool {
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
    var fifo = try FifoQueue(u8, .Alloc).init(allocator, .{
        .init_capacity = 4,
        .growable = true,
        .shrinkable = true,
    });
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
    var fifo = FifoQueue(u8, .Buffer).init(&buffer, .{});

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
        var fifo = FifoQueue(u8, .Comptime).init(.{
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
