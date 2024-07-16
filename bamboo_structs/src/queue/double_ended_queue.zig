//! Author: palsmo
//! Read: https://en.wikipedia.org/wiki/Double-ended_queue

const std = @import("std");

const maple = @import("maple_utils");

const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const Error = shared.Error;
const assertAndMsg = maple.debug.assertAndMsg;
const assertPowOf2 = maple.math.assertPowOf2;
const panic = std.debug.panic;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// Queue items of type `T`, specify `buffer_type` (for branch pruning).
/// Useful when flexibility and efficiency is required.
/// Properties:
/// Uses 'Ring Buffer' logic under the hood.
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
pub fn DoubleEndedQueue(comptime T: type, comptime buffer_type: enum { Alloc, Buffer, Comptime }) type {
    return struct {
        const Self = @This();

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
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the queue, will reference one of:
        /// - initAlloc(options: Options, allocator: Allocator) !Self
        /// - initBuffer(buf: []T, options: Options) Self
        /// - initComptime(comptime options: Options) Self
        pub const init = switch (buffer_type) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the queue, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        fn initAlloc(options: Options, allocator: Allocator) !Self {
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Currently `options` will be ignored.
        fn initBuffer(buf: []T, options: Options) Self {
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

        /// Initialize the queue, allocating memory in read-only data or
        /// compiler's address space if not referenced runtime.
        fn initComptime(comptime options: Options) Self {
            assertAndMsg(@inComptime(), "Invalid at runtime.", .{});
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = b: { // not 'free-after-use', compiler promotes
                    var buf: [options.init_capacity]T = undefined;
                    break :b &buf;
                },
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
            // grow?
            if (self.size < self.buffer.len) {} else {
                switch (buffer_type) {
                    .Alloc, .Comptime => if (self.options.growable) try self.grow() else return Error.Overflow,
                    .Buffer => return Error.Overflow,
                }
            }

            if (self.size != 0) {
                self.head = wrapDecrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip decrement, `head` already points to valid slot

            self.buffer[self.head] = item;
            self.size += 1;
        }

        /// Store an `item` last in the queue.
        pub inline fn push_last(self: *Self, item: T) !void {
            // grow?
            if (self.size < self.buffer.len) {} else {
                switch (buffer_type) {
                    .Alloc, .Comptime => if (self.options.growable) try self.grow() else return Error.Overflow,
                    .Buffer => return Error.Overflow,
                }
            }

            if (self.size != 0) {
                self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip increment, `tail` already points to valid slot

            self.buffer[self.tail] = item;
            self.size += 1;
        }

        /// Get an item first in the queue, free its memory.
        pub inline fn pop_first(self: *Self) !T {
            if (self.size != 0) {} else return Error.Underflow;

            const item = self.buffer[self.head];
            if (self.size > 1) {
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip increment, `head` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (buffer_type) {
                .Alloc, .Comptime => {
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
                .Buffer => {},
            }

            return item;
        }

        /// Get an item last in the queue, free its memory.
        pub inline fn pop_last(self: *Self) !T {
            if (self.size != 0) {} else return Error.Underflow;

            const item = self.buffer[self.tail];
            if (self.size > 1) {
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip decrement, `tail` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (buffer_type) {
                .Alloc, .Comptime => {
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
                .Buffer => {},
            }

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

        /// Reset queue to its empty state.
        pub fn reset(self: *Self) !void {
            // allocate new buffer with initial capacity
            if (self.buffer.len != self.options.init_capacity) {
                self.buffer = switch (buffer_type) {
                    .Alloc => b: {
                        self.allocator.?.free(self.buffer);
                        break :b try self.allocator.?.alloc(T, self.options.init_capacity);
                    },
                    .Comptime => b: { // not 'free-after-use', compiler promotes
                        var buf: [self.options.init_capacity]T = undefined;
                        break :b &buf;
                    },
                    .Buffer => self.buffer,
                };
            }

            self.head = 0;
            self.tail = 0;
            self.size = 0;
        }

        /// Check if the queue is empty.
        pub inline fn isEmpty(self: *Self) bool {
            return self.size == 0;
        }

        /// Copy over current content into new buffer of twice the size.
        fn grow(self: *Self) !void {
            // allocate new buffer with more capacity
            const new_buffer = switch (buffer_type) {
                .Alloc => b: {
                    const new_cap = self.buffer.len * 2;
                    break :b try self.allocator.?.alloc(T, new_cap);
                },
                .Comptime => b: { // not 'free-after-use', compiler promotes
                    const new_cap = self.buffer.len * 2;
                    var buf: [new_cap]T = undefined;
                    break :b &buf;
                },
                .Buffer => unreachable,
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

            if (buffer_type == .Alloc) self.allocator.?.free(self.buffer);

            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.size - 1;
        }

        /// Copy over current content into a new buffer of half the size.
        fn shrink(self: *Self) !void {
            // allocate new buffer with less capacity
            const new_buffer = switch (buffer_type) {
                .Alloc => b: {
                    const new_cap = self.buffer.len / 2;
                    break :b try self.allocator.?.alloc(T, new_cap);
                },
                .Comptime => b: { // not 'free-after-use', compiler promotes
                    const new_cap = self.buffer.len / 2;
                    var buf: [new_cap]T = undefined;
                    break :b &buf;
                },
                .Buffer => unreachable,
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

            if (buffer_type == .Alloc) self.allocator.?.free(self.buffer);

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

test "Allocated DoubleEndedQueue" {
    const allocator = std.testing.allocator;
    var deque = try DoubleEndedQueue(u8, .Alloc).init(.{
        .init_capacity = 4,
        .growable = true,
        .shrinkable = true,
    }, allocator);
    defer deque.deinit();

    // test empty state -->

    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.pop_first());
    try expectError(Error.Underflow, deque.pop_last());
    try expectEqual(null, deque.peek_first());
    try expectEqual(null, deque.peek_last());

    // test basic push and pop -->

    try deque.push_first(1);
    try deque.push_last(2);
    try expectEqual(1, try deque.pop_first());
    try expectEqual(2, try deque.pop_last());

    // x x x x
    //   ^.---.
    //   tail head

    try expect(deque.head == deque.tail);
    try expect(deque.isEmpty());

    try deque.reset();

    // test wrapping behavior -->

    try deque.push_last(1);
    try deque.push_last(2);
    try deque.push_last(3);
    try deque.push_last(4);
    _ = try deque.pop_first();
    try deque.push_last(5);

    // 5 2 3 4
    // ^ ^--.
    // tail head

    try expectEqual(0, deque.tail); // tail wrap

    _ = try deque.pop_last();
    _ = try deque.pop_last();
    try deque.push_first(4);
    try deque.push_first(5);

    // 4 2 3 5
    //     ^ ^--.
    //     tail head

    try expectEqual(3, deque.head); // head wrap

    // test shrink (pop_first) -->

    deque.options.init_capacity = 8;
    try deque.reset();
    deque.options.init_capacity = 2;

    try deque.push_first(1);
    try deque.push_last(2);
    try deque.push_first(3);

    // 2 x x x x x 3 1
    // ^           ^
    // tail        head

    try expectEqual(8, deque.buffer.len);
    _ = try deque.pop_first(); // shrink trigger
    try expectEqual(4, deque.buffer.len);

    // 1 2 x x
    // ^ ^--.
    // head tail

    try expectEqual(1, deque.buffer[0]);
    try expectEqual(2, deque.buffer[1]);

    // test growth (push_first) -->

    try deque.push_first(3);
    try deque.push_first(4);

    // 1 2 4 3
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.buffer.len);
    try deque.push_first(5); // growth trigger
    try expectEqual(8, deque.buffer.len);

    // 4 3 1 2 x x 5
    //         ^   ^.
    //         tail head

    try expectEqual(4, deque.buffer[0]);
    try expectEqual(3, deque.buffer[1]);
    try expectEqual(1, deque.buffer[2]);
    try expectEqual(2, deque.buffer[3]);
    try expectEqual(5, deque.buffer[7]);

    // test shrink (pop_last) -->

    _ = try deque.pop_first();
    _ = try deque.pop_first();

    // x x 3 1 2 x x x
    //     ^   ^.
    //     head tail

    deque.options.init_capacity = 2;

    try expectEqual(8, deque.buffer.len);
    _ = try deque.pop_first(); // shrink trigger
    try expectEqual(4, deque.buffer.len);

    // 1 2 x x
    // ^ ^--.
    // head tail

    try expectEqual(1, deque.buffer[0]);
    try expectEqual(2, deque.buffer[1]);

    deque.options.init_capacity = 4;

    // test growth (push_first) -->

    try deque.push_first(3);
    try deque.push_first(4);

    // 1 2 4 3
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.buffer.len);
    try deque.push_last(5); // growth trigger
    try expectEqual(8, deque.buffer.len);

    // 4 3 1 2 5 x x x
    // ^       ^
    // head    tail

    try expectEqual(4, try deque.pop_first());
    try expectEqual(3, try deque.pop_first());
    try expectEqual(1, try deque.pop_first());
    try expectEqual(2, try deque.pop_first());
    try expectEqual(5, try deque.pop_first());
}

test "Buffered DoubleEndedQueue" {
    var buffer: [2]u8 = undefined;
    var deque = DoubleEndedQueue(u8, .Buffer).init(&buffer, .{});

    // test general -->

    try deque.push_first(1);
    try deque.push_last(2);
    try expectError(Error.Overflow, deque.push_first(3));
    try expectError(Error.Overflow, deque.push_last(4));
    try expectEqual(1, try deque.pop_first());
    try expectEqual(2, try deque.pop_last());
    try expect(deque.isEmpty());
}

test "Comptime DoubleEndedQueue" {
    comptime {
        var deque = DoubleEndedQueue(u8, .Comptime).init(.{ .init_capacity = 4 });

        // test general -->

        try deque.push_first(1);
        try deque.push_last(2);
        try expectEqual({}, deque.push_first(3));
        try expectEqual({}, deque.push_last(4));
        try expectEqual(3, try deque.pop_first());
        try expectEqual(4, try deque.pop_last());
        try expectEqual(1, try deque.pop_first());
        try expectEqual(2, try deque.pop_last());
        try expect(deque.isEmpty());
    }
}
