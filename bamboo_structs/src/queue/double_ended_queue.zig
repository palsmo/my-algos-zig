//! Author: palsmo
//! Read: https://en.wikipedia.org/wiki/Double-ended_queue

const std = @import("std");

const maple = @import("maple_utils");

const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const Error = shared.Error;
const panic = std.debug.panic;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// Queue items of type `T`.
/// Useful when flexibility and efficiency is required.
/// Properties:
/// Uses 'Ring Buffer' logic under the hood.
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
pub fn DoubleEndedQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue
            init_capacity: usize = 64,
            // whether the map can grow beyond `init_capacity`
            growable: bool = true,
        };

        // struct fields
        buffer: []T,
        buffer_type: enum { Alloc, Buffer, Comptime },
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the queue, configure with `options`.
        /// After use; release memory by calling 'deinit'.
        pub fn init(options: Options, allocator: Allocator) !Self {
            return @call(.always_inline, initAlloc, .{ options, allocator });
        }

        /// Initialize the queue, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        pub fn initAlloc(options: Options, allocator: Allocator) !Self {
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .buffer_type = .Alloc,
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Won't be able to grow, `options.growable` and `options.init_capacity` is ignored.
        pub fn initBuffer(buf: []T, options: Options) Self {
            if (buf.len == 0) panic("Can't initialize with zero size.", .{});

            var _options = options;
            _options.init_capacity = buf.len;
            _options.growable = false;

            return .{
                .buffer = buf,
                .buffer_type = .Buffer,
                .options = _options,
                .allocator = null,
            };
        }

        /// Initialize the queue, allocating memory in read-only data or
        /// compiler's address space if not referenced runtime.
        pub fn initComptime(comptime options: Options) Self {
            if (!@inComptime()) panic("Invalid at runtime.", .{});
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});

            return .{
                .buffer = b: { // compiler promotes, not 'free-after-use'
                    var buf: [options.init_capacity]T = undefined;
                    break :b &buf;
                },
                .buffer_type = .Comptime,
                .options = options,
                .allocator = null,
            };
        }

        /// Release allocated memory, cleanup routine for 'init' and 'initAlloc'.
        pub fn deinit(self: *Self) void {
            if (self.allocator) |ally| {
                ally.free(self.buffer);
            } else {
                panic("Can't use `null` allocator.", .{});
            }
        }

        /// Store an `item` first in the queue.
        pub inline fn push_first(self: *Self, item: T) !void {
            if (self.size >= self.buffer.len) {
                if (self.options.growable) try self.grow() else return Error.Overflow;
            }
            if (self.size != 0) {
                self.head = wrapDecrement(usize, self.head, 0, self.buffer.len);
            } else {
                // * skip decrement, `head` already points to valid slot
            }
            self.buffer[self.head] = item;
            self.size += 1;
        }

        /// Store an `item` last in the queue.
        pub inline fn push_last(self: *Self, item: T) !void {
            if (self.size >= self.buffer.len) {
                if (self.options.growable) try self.grow() else return Error.Overflow;
            }
            if (self.size != 0) {
                self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len);
            } else {
                // * skip increment, `tail` already points to valid slot
            }
            self.buffer[self.tail] = item;
            self.size += 1;
        }

        /// Get an item first in the queue, free its memory.
        pub inline fn pop_first(self: *Self) !T {
            if (self.size == 0) return Error.Underflow;

            const item = self.buffer[self.head];
            if (self.size > 1) {
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            } else {
                // * skip increment, `head` already points to valid slot
            }
            self.size -= 1;
            return item;
        }

        /// Get an item last in the queue, free its memory.
        pub inline fn pop_last(self: *Self) !T {
            if (self.size == 0) return Error.Underflow;

            const item = self.buffer[self.tail];
            if (self.size > 1) {
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            } else {
                // * skip decrement, `tail` already points to valid slot
            }
            self.size -= 1;
            return item;
        }

        /// Get an item first in the queue.
        pub inline fn peek_first(self: *Self) ?T {
            if (self.size == 0) return null;

            const item = self.buffer[self.head];
            return item;
        }

        /// Get an item last in the queue.
        pub inline fn peek_last(self: *Self) ?T {
            if (self.size == 0) return null;

            const item = self.buffer[self.tail];
            return item;
        }

        /// Check if the queue is empty.
        pub inline fn isEmpty(self: *Self) bool {
            return self.size == 0;
        }

        /// Copy over current content into new buffer of twice the size.
        fn grow(self: *Self) !void {
            // allocate buffer with more capacity
            const new_capacity = self.buffer.len * 2;
            const new_buffer = switch (self.buffer_type) {
                .Alloc => try self.allocator.?.alloc(T, new_capacity),
                .Buffer => unreachable,
                .Comptime => b: { // compiler promotes, not 'free-after-use'
                    if (!@inComptime()) panic("Can't grow comptime buffer at runtime.", .{});
                    var buf: [new_capacity]T = undefined;
                    break :b &buf;
                },
            };

            if (self.head <= self.tail) {
                // * `tail` is not wrapped around

                // copy over whole part
                const old_mem = self.buffer[self.head .. self.tail + 1];
                const new_mem = new_buffer[0..old_mem.len];
                @memcpy(new_mem, old_mem);
            } else {
                // * `head` or/and `tail` is wrapped around

                // copy over first part
                const old_mem_a = self.buffer[self.head..self.buffer.len];
                const new_mem_a = new_buffer[0..old_mem_a.len];
                @memcpy(new_mem_a, old_mem_a);

                // copy over second part
                const old_mem_b = self.buffer[0 .. self.tail + 1];
                const new_mem_b = new_buffer[old_mem_a.len .. old_mem_a.len + self.tail + 1];
                @memcpy(new_mem_b, old_mem_b);
            }

            if (self.buffer_type == .Alloc) self.allocator.?.free(self.buffer);

            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.size - 1;
        }
    };
}

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "static DoubleEndedQueue" {
    // setup
    var buffer: [4]u8 = undefined;
    var deque = DoubleEndedQueue(u8).initBuffer(&buffer, .{});

    // test general
    try deque.push_first(1);
    try deque.push_last(2);
    try deque.push_first(3);
    try deque.push_last(4);

    try expectError(Error.Overflow, deque.push_first(5));
    try expectError(Error.Overflow, deque.push_last(5));
    try expectEqual(@as(u8, 3), try deque.pop_first());
    try expectEqual(@as(u8, 4), try deque.pop_last());
    try expectEqual(@as(u8, 1), try deque.pop_first());
    try expectEqual(@as(u8, 2), try deque.pop_last());
    try expectEqual(true, deque.isEmpty());
}

test "dynamic DoubleEndedQueue" {
    // setup
    const allocator = std.testing.allocator;
    var deque = try DoubleEndedQueue(u8).init(.{ .init_capacity = 4, .growable = true }, allocator);
    defer deque.deinit();

    // test empty state
    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.pop_first());
    try expectError(Error.Underflow, deque.pop_last());
    try expectEqual(@as(?u8, null), deque.peek_first());
    try expectEqual(@as(?u8, null), deque.peek_last());

    // test basic push and pop
    try deque.push_first(1);
    try deque.push_last(2);
    try expectEqual(@as(u8, 1), try deque.pop_first());
    try expectEqual(@as(u8, 2), try deque.pop_last());
    try expect(deque.head == deque.tail);
    try expectEqual(true, deque.isEmpty());

    // test wrapping behavior
    try deque.push_last(3);
    try deque.push_last(4);
    try deque.push_last(5);
    try deque.push_last(6);
    _ = try deque.pop_first();
    _ = try deque.pop_first();
    // x x 5 6
    //     ^ ^--.
    //     head tail
    try deque.push_last(7);
    try deque.push_last(8);

    try expectEqual(@as(u8, 5), try deque.pop_first());
    try expectEqual(@as(u8, 6), try deque.pop_first());
    try expectEqual(@as(u8, 7), try deque.pop_first());
    try expectEqual(@as(u8, 8), try deque.pop_first());

    // test growth
    var i: u8 = 0;
    while (i < 9) : (i += 1) try deque.push_last(i);
    i = 0;
    while (i < 9) : (i += 1) try expectEqual(i, try deque.pop_first());
}

//test "peek" {
//    comptime {
//        const T = u8;
//        var deque = DoubleEndedQueue(T).initComptime(.{ .init_capacity = 2, .growable = false });
//
//        const value_a: T = 4;
//        const value_b: T = 5;
//        deque.push_first(value_a) catch unreachable;
//        deque.push_last(value_b) catch unreachable;
//        const result_a = deque.peek_first();
//        const result_b = deque.peek_last();
//
//        expectEqual(value_a, result_a) catch unreachable;
//        expectEqual(value_b, result_b) catch unreachable;
//    }
//}
//
//test "push and pop (comptime)" {
//    comptime {
//        const T = u8;
//        var deque = DoubleEndedQueue(T).initComptime(.{ .init_capacity = 3, .growable = false });
//
//        const value_a: T = 4;
//        const value_b: T = 5;
//        const value_c: T = 6;
//        deque.push_first(value_a) catch unreachable;
//        deque.push_last(value_b) catch unreachable;
//        deque.push_last(value_c) catch unreachable;
//        const result_a = deque.pop_first();
//        const result_b = deque.pop_first();
//        const result_c = deque.pop_last();
//
//        expectEqual(value_a, result_a) catch unreachable;
//        expectEqual(value_b, result_b) catch unreachable;
//        expectEqual(value_c, result_c) catch unreachable;
//    }
//}
//
//test "push and pop (runtime)" {
//    const allocator = std.testing.allocator;
//
//    const T = u8;
//    var deque = try DoubleEndedQueue(T).initAlloc(.{ .init_capacity = 1, .growable = false }, allocator);
//    defer deque.deinit();
//
//    const value: T = 4;
//    try deque.push_first(value);
//    const result = deque.pop_first();
//
//    try expectEqual(value, result);
//}
//
//test "peek empty queue expect null" {
//    comptime {
//        var deque = DoubleEndedQueue(u8).initComptime(.{ .init_capacity = 1, .growable = false });
//
//        const result_a = deque.peek_first();
//        const result_b = deque.peek_last();
//
//        expectEqual(null, result_a) catch unreachable;
//        expectEqual(null, result_b) catch unreachable;
//    }
//}
//
//test "pop empty queue expect underflow error" {
//    comptime {
//        const T = u8;
//        var deque = DoubleEndedQueue(T).initComptime(.{ .init_capacity = 1, .growable = false });
//
//        const result_a = deque.pop_first();
//        const result_b = deque.pop_last();
//
//        expectError(Error.Underflow, result_a) catch unreachable;
//        expectError(Error.Underflow, result_b) catch unreachable;
//    }
//}
//
//test "push too many expect overflow error" {
//    comptime {
//        const T = u8;
//        var deque = DoubleEndedQueue(T).initComptime(.{ .init_capacity = 1, .growable = false });
//
//        const value: T = 4;
//        _ = deque.push_first(value) catch unreachable;
//        const result_a = deque.push_first(value);
//        const result_b = deque.push_last(value);
//
//        expectError(Error.Overflow, result_a) catch unreachable;
//        expectError(Error.Overflow, result_b) catch unreachable;
//    }
//}
//
//test "push too many expect growable queue to grow" {
//    comptime {
//        const T = u8;
//        var deque = DoubleEndedQueue(T).initComptime(.{ .init_capacity = 1, .growable = true });
//
//        const value_a: T = 4;
//        const value_b: T = 5;
//        const value_c: T = 6;
//        const value_d: T = 7;
//        deque.push_first(value_a) catch unreachable;
//        deque.push_last(value_b) catch unreachable;
//        deque.push_first(value_c) catch unreachable;
//        deque.push_first(value_d) catch unreachable;
//        // a b d c
//        //   ^ ^---
//        //   tail head
//        const result_d = deque.pop_first();
//        const result_b = deque.pop_last();
//        const result_c = deque.pop_first();
//        const result_a = deque.pop_last();
//
//        expectEqual(value_a, result_a) catch unreachable;
//        expectEqual(value_b, result_b) catch unreachable;
//        expectEqual(value_c, result_c) catch unreachable;
//        expectEqual(value_d, result_d) catch unreachable;
//
//        expectEqual(4, deque.buffer.len) catch unreachable;
//    }
//}
