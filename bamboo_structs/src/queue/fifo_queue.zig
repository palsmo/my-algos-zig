//! Author: palsmo
//! Read: https://en.wikipedia.org/wiki/FIFO_(computing_and_electronics)

const std = @import("std");

const _deque = @import("./double_ended_queue.zig");
const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const DoubleEndedQueue = _deque.DoubleEndedQueue;
const Error = shared.Error;

/// Queue items of type `T` with First-In-First-Out behavior.
/// Useful when flexibility and efficiency is wanted.
/// Properties:
/// Uses 'DoubleEndedQueue' logic under the hood.
/// Low memory, good cache locality.
///
/// complexity |     best     |   average    |    worst     |        factor
/// ---------- | ------------ | ------------ | ------------ | ---------------------
/// memory     | O(1)         | O(1)         | O(n)         | grow routine
/// space      | O(n)         | O(n)         | O(2n)        | grow routine
/// insertion  | O(1)         | O(1)         | O(n)         | grow routine
/// deletion   | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup     | O(1)         | O(1)         | O(n log n)   | space saturation
/// -------------------------------------------------------------------------------
pub fn FifoQueue(comptime T: type, comptime buffer_type: enum { Alloc, Buffer, Comptime }) type {
    return struct {
        const Self = @This();
        const Dequ = DoubleEndedQueue(T, buffer_type);

        pub const Options = struct {
            // initial capacity of the queue
            init_capacity: usize = 64,
            // whether the map can grow beyond `init_capacity`
            growable: bool = true,
            // whether the map can shrink a grow,
            // will half when size used falls below 1/4 of allocated
            shrinkable: bool = true,
        };

        // struct fields
        deque: Dequ,

        /// Initialize the queue, will reference one of:
        /// - initAlloc(options, Options, allocator: Allocator) !Self
        /// - initBuffer(buf: []T, options: Options) Self
        /// - initComptime(comptime options: Options) Self
        pub const init = switch (buffer_type) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the queue, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        pub fn initAlloc(options: Options, allocator: Allocator) !Self {
            const _options: Dequ.Options = .{
                .init_capacity = options.init_capacity,
                .growable = options.growable,
                .shrinkable = options.shrinkable,
            };
            return .{ .body = try Dequ.init(_options, allocator) };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Won't be able to grow, `options.growable` and `options.init_capacity` is ignored.
        pub fn initBuffer(buf: []T, options: Options) Self {
            const _options: Dequ.Options = .{
                .init_capacity = options.init_capacity,
                .growable = options.growable,
                .shrinkable = options.shrinkable,
            };
            return .{ .body = Dequ.init(buf, _options) };
        }

        /// Initialize the queue, allocating memory in read-only data or
        /// compiler's address space if not referenced runtime.
        pub fn initComptime(comptime options: Options) Self {
            const _options: Dequ.Options = .{
                .init_capacity = options.init_capacity,
                .growable = options.growable,
                .shrinkable = options.shrinkable,
            };
            return .{ .body = Dequ.init(_options) };
        }

        /// Release allocated memory, cleanup routine for 'init' and 'initAlloc'.
        pub fn deinit(self: *Self) void {
            self.deque.deinit();
        }

        /// Store an `item` last in the queue.
        pub fn push(self: *Self, item: T) !void {
            return self.deque.push_last(item);
        }

        /// Get an item first in the queue, free its memory.
        pub fn pop(self: *Self) !T {
            return self.deque.pop_first();
        }

        /// Get an item first in the queue.
        pub fn peek(self: *Self) ?T {
            return self.deque.peek_first();
        }

        /// Check if the queue is empty.
        pub inline fn isEmpty(self: *Self) bool {
            return self.deque.isEmpty();
        }
    };
}

// testing -->

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Static FifoQueue" {
    // setup
    var buffer: [2]u8 = undefined;
    var fifo = FifoQueue(u8, .Buffer).initBuffer(&buffer, .{});

    // test general
    try fifo.push(1);
    try fifo.push(2);

    try expectError(Error.Overflow, fifo.push(3));
    try expectEqual(@as(u8, 1), try fifo.pop());
    try expectEqual(@as(u8, 2), try fifo.pop());
    try expectEqual(true, fifo.isEmpty());
}

test "Dynamic FifoQueue" {
    // setup
    const allocator = std.testing.allocator;
    var fifo = try FifoQueue(u8, .Alloc).init(.{
        .init_capacity = 2,
        .growable = true,
        .shrinkable = true,
    }, allocator);
    defer fifo.deinit();

    // test empty state
    try expectEqual(true, fifo.isEmpty());
    try expectError(Error.Underflow, fifo.pop());
    try expectEqual(@as(?u8, null), fifo.peek());

    // test basic push and pop
    try fifo.push(1);
    try expectEqual(@as(u8, 1), try fifo.pop());
    try expectEqual(true, fifo.isEmpty());

    // test growth
    var i: u8 = 0;
    while (i < 5) : (i += 1) try fifo.push(i);
    i = 0;
    while (i < 5) : (i += 1) try expectEqual(i, try fifo.pop());
}
