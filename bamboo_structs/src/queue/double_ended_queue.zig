//! Author: palsmo
//! Status: Done
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

/// A double-ended queue (deque) for items of type `T`.
/// Useful as primitive for other structures.
/// Provides efficient insertion, removal and lookup operations at both ends.
///
/// Reference to 'self.buffer' may become invalidated after grow/shrink routine,
/// use 'self.isValidRef' to verify.
///
/// Properties:
/// Uses 'Ring Buffer' logic under the hood.
///
///  complexity |     best     |   average    |    worst     |        factor
/// ------------|--------------|--------------|--------------|----------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink routine
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink routine
/// insertion   | O(1)         | O(1)         | O(n)         | grow routine
/// deletion    | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup      | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|----------------------
///  cache loc  | good         | good         | decent       | usage pattern (wrap)
/// --------------------------------------------------------------------------------
pub fn DoubleEndedQueue(comptime T: type) type {
    return struct {
        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 64,
            // whether the queue can grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        /// Initialize the queue, allocating memory on the heap.
        /// User should release memory after use by calling 'deinit'.
        /// Function is valid only during _runtime_.
        pub fn initAlloc(options: Options, allocator: Allocator) !DoubleEndedQueueGeneric(T, .Alloc) {
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Fields in `options` that will be ignored are; init_capacity, growable, shrinkable.
        /// Function is valid during _comptime_ or _runtime_.
        pub fn initBuffer(buf: []T, options: Options) DoubleEndedQueueGeneric(T, .Buffer) {
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

        /// Initialize the queue, allocating memory in .rodata or
        /// compiler's address space if not referenced runtime.
        /// Function is valid during _comptime_.
        pub fn initComptime(comptime options: Options) DoubleEndedQueueGeneric(T, .Comptime) {
            assertAndMsg(@inComptime(), "Function 'initComptime' is invalid runtime (prefix with 'comptime').", .{});
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
    };
}

/// Digest of some 'DoubleEndedQueue' init-function.
/// Depending on `buffer_type` certain operations may be pruned or optimized.
pub fn DoubleEndedQueueGeneric(comptime T: type, comptime buffer_type: enum { Alloc, Buffer, Comptime }) type {
    return struct {
        const Self = @This();

        const Deque = DoubleEndedQueue(T);

        // struct fields
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,
        options: Deque.Options,
        allocator: ?Allocator,

        /// Release allocated memory, cleanup routine for 'initAlloc'.
        pub fn deinit(self: *Self) void {
            switch (buffer_type) {
                .Alloc => self.allocator.?.free(self.buffer),
                .Buffer, .Comptime => panic("Can't deallocate with nonexistent allocator.", .{}),
            }
        }

        pub inline fn pushFirstInline(self: *Self, item: T) !void {
            try @call(.always_inline, pushFirst, .{ self, item });
        }

        /// Store an `item` first in the queue.
        /// This function throws error when adding at max capacity with 'self.options.growable' set to false.
        pub fn pushFirst(self: *Self, item: T) !void {
            // grow?
            if (self.size < self.buffer.len) {} else {
                switch (buffer_type) {
                    .Alloc => if (self.options.growable) try self.grow() else return Error.Overflow,
                    .Buffer => return Error.Overflow,
                    .Comptime => {
                        assertAndMsg(@inComptime(), "Function 'pushFirst' (comptime version) is invalid at runtime (prefix with 'comptime').", .{});
                        if (self.options.growable) try self.grow() else return Error.Overflow;
                    },
                }
            }

            if (self.size != 0) {
                self.head = wrapDecrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip decrement, `head` already points to valid slot

            self.buffer[self.head] = item;
            self.size += 1;
        }

        pub inline fn pushLastInline(self: *Self, item: T) !void {
            try @call(.always_inline, pushLast, .{ self, item });
        }

        /// Store an `item` last in the queue.
        /// This function throws error when adding at max capacity with 'self.options.growable' set to false.
        pub fn pushLast(self: *Self, item: T) !void {
            // grow?
            if (self.size < self.buffer.len) {} else {
                switch (buffer_type) {
                    .Alloc => if (self.options.growable) try self.grow() else return Error.Overflow,
                    .Buffer => return Error.Overflow,
                    .Comptime => {
                        assertAndMsg(@inComptime(), "Function 'pushLast' (comptime version) is invalid at runtime (prefix with 'comptime').", .{});
                        if (self.options.growable) try self.grow() else return Error.Overflow;
                    },
                }
            }

            if (self.size != 0) {
                self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip increment, `tail` already points to valid slot

            self.buffer[self.tail] = item;
            self.size += 1;
        }

        pub inline fn popFirstInline(self: *Self) !T {
            return try @call(.always_inline, popFirst, .{self});
        }

        /// Get the first item in the queue, free its memory.
        /// This function throws error when trying to release from empty queue.
        pub fn popFirst(self: *Self) !T {
            if (self.size != 0) {} else return Error.Underflow;

            const item = self.buffer[self.head];
            if (self.size > 1) {
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip increment, `head` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (buffer_type) {
                .Alloc => {
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
                .Buffer => {},
                .Comptime => {
                    assertAndMsg(@inComptime(), "Function 'popFirst' (comptime version) is invalid at runtime (prefix with 'comptime').", .{});
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
            }

            return item;
        }

        pub inline fn popLastInline(self: *Self) !T {
            return try @call(.always_inline, popLast, .{self});
        }

        /// Get the last item in the queue, free its memory.
        /// This function throws error when trying to release from empty queue.
        pub fn popLast(self: *Self) !T {
            if (self.size != 0) {} else return Error.Underflow;

            const item = self.buffer[self.tail];
            if (self.size > 1) {
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip decrement, `tail` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (buffer_type) {
                .Alloc => {
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
                .Buffer => {},
                .Comptime => {
                    assertAndMsg(@inComptime(), "Function 'popLast' (comptime version) is invalid at runtime (prefix with 'comptime').", .{});
                    if (self.options.shrinkable) {
                        if (self.size >= self.options.init_capacity) {
                            if (self.size > self.buffer.len / 4) {} else try self.shrink();
                        }
                    }
                },
            }

            return item;
        }

        pub inline fn peekFirstInline(self: *Self) ?T {
            return @call(.always_inline, peekFirst, .{self});
        }

        /// Get the first item in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekFirst(self: *Self) ?T {
            if (self.size != 0) {} else return null;
            return self.buffer[self.head];
        }

        pub inline fn peekLastInline(self: *Self) ?T {
            return @call(.always_inline, peekLast, .{self});
        }

        /// Get the last item in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekLast(self: *Self) ?T {
            if (self.size != 0) {} else return null;
            return self.buffer[self.tail];
        }

        pub inline fn peekIndexInline(self: *Self) ?T {
            return @call(.always_inline, peekIndex, .{self});
        }

        /// Get an item at index `index` in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekIndex(self: *Self, index: usize) ?T {
            if (self.size > index) {} else return null;
            const sum = self.head +% index;
            const actual_index = sum % self.buffer.len;
            return self.buffer[actual_index];
        }

        /// Get current amount of 'T' that's buffered in the queue.
        pub inline fn capacity(self: *Self) usize {
            return self.buffer.len;
        }

        /// Get current amount of 'T' that's occupying the queue.
        pub inline fn length(self: *Self) usize {
            return self.size;
        }

        /// Reset queue to its empty state.
        /// This function may throw error as part of the allocation process.
        pub fn reset(self: *Self) !void {
            // allocate new buffer with initial capacity
            if (self.buffer.len != self.options.init_capacity) {
                switch (buffer_type) {
                    .Alloc => {
                        self.allocator.?.free(self.buffer);
                        self.buffer = try self.allocator.?.alloc(T, self.options.init_capacity);
                    },
                    .Comptime => { // not 'free-after-use', compiler promotes
                        assertAndMsg(@inComptime(), "Function 'reset' (comptime version) is invalid at runtime (prefix with 'comptime').", .{});
                        var buf: [self.options.init_capacity]T = undefined;
                        self.buffer = &buf;
                    },
                    .Buffer => {},
                }
            }

            self.head = 0;
            self.tail = 0;
            self.size = 0;
        }

        /// Check if the queue is empty.
        /// Returns _true_ (empty) or _false_ (not empty).
        pub inline fn isEmpty(self: *Self) bool {
            return self.size == 0;
        }

        /// Check if the queue is full.
        /// Returns _true_ (full) or _false_ (not full).
        pub inline fn isFull(self: *Self) bool {
            return self.size == self.buffer.len;
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        /// Returns _true_ (valid ref) or _false_ (invalid ref).
        pub inline fn isValidRef(self: *Self, ptr: *[]T) bool {
            return ptr == &self.buffer;
        }

        /// Copy over current content into new buffer of twice the size.
        /// This function may throw error as part of the allocation process.
        fn grow(self: *Self) !void {
            // allocate new buffer with more capacity
            const new_capacity = try std.math.mul(usize, self.buffer.len, 2);
            const new_buffer = switch (buffer_type) {
                .Alloc => try self.allocator.?.alloc(T, new_capacity),
                .Buffer => unreachable,
                .Comptime => b: { // not 'free-after-use', compiler promotes
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

            if (buffer_type == .Alloc) self.allocator.?.free(self.buffer);

            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.size - 1;
        }

        /// Copy over current content into a new buffer of half the size.
        /// This function may throw error as part of the allocation process.
        fn shrink(self: *Self) !void {
            // allocate new buffer with less capacity
            const new_capacity = try std.math.divExact(usize, self.buffer.len, 2);
            const new_buffer = switch (buffer_type) {
                .Alloc => try self.allocator.?.alloc(T, new_capacity),
                .Comptime => b: { // not 'free-after-use', compiler promotes
                    var buf: [new_capacity]T = undefined;
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
    var deque = try DoubleEndedQueue(u8).initAlloc(.{
        .init_capacity = 4,
        .growable = true,
        .shrinkable = true,
    }, allocator);
    defer deque.deinit();

    // test empty state -->

    try expectEqual(4, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.popFirst());
    try expectError(Error.Underflow, deque.popLast());
    try expectEqual(null, deque.peekFirst());
    try expectEqual(null, deque.peekLast());
    try expectEqual(null, deque.peekIndex(0));

    // test basic push and pop -->

    try deque.pushFirst(1);
    try deque.pushLast(2);
    try expectEqual(2, deque.length());
    try expectEqual(1, try deque.popFirst());
    try expectEqual(2, try deque.popLast());

    // x x x x
    //   ^.---.
    //   tail head

    try expectEqual(true, deque.head == deque.tail);
    try expectEqual(true, deque.isEmpty());

    try deque.reset();

    // test wrapping behavior -->

    try deque.pushLast(1);
    try deque.pushLast(2);
    try deque.pushLast(3);
    try deque.pushLast(4);
    _ = try deque.popFirst();
    try deque.pushLast(5);

    // 5 2 3 4
    // ^ ^--.
    // tail head

    try expectEqual(0, deque.tail); // tail wrap

    _ = try deque.popLast();
    _ = try deque.popLast();
    try deque.pushFirst(4);
    try deque.pushFirst(5);

    // 4 2 3 5
    //     ^ ^--.
    //     tail head

    try expectEqual(3, deque.head); // head wrap

    // test shrink ('popFirst') -->

    deque.options.init_capacity = 8;
    try deque.reset();
    deque.options.init_capacity = 2;

    try deque.pushFirst(1);
    try deque.pushLast(2);
    try deque.pushFirst(3);

    // 2 x x x x x 3 1
    // ^           ^
    // tail        head

    try expectEqual(8, deque.capacity());
    _ = try deque.popFirst(); // shrink trigger
    try expectEqual(4, deque.capacity());

    // 1 2 x x
    // ^ ^--.
    // head tail

    try expectEqual(1, deque.peekIndex(0));
    try expectEqual(2, deque.peekIndex(1));
    try expectEqual(null, deque.peekIndex(2));

    // test grow ('pushFirst') -->

    try deque.pushFirst(3);
    try deque.pushFirst(4);
    try expectEqual(true, deque.isFull());

    // 1 2 4 3
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.capacity());
    try deque.pushFirst(5); // growth trigger
    try expectEqual(8, deque.capacity());

    // 4 3 1 2 x x 5
    //         ^   ^.
    //         tail head

    try expectEqual(4, deque.buffer[0]);
    try expectEqual(3, deque.buffer[1]);
    try expectEqual(1, deque.buffer[2]);
    try expectEqual(2, deque.buffer[3]);
    try expectEqual(5, deque.buffer[7]);

    // test shrink ('popLast') -->

    _ = try deque.popFirst();
    _ = try deque.popFirst();

    // x x 3 1 2 x x x
    //     ^   ^.
    //     head tail

    deque.options.init_capacity = 2;

    try expectEqual(8, deque.capacity());
    _ = try deque.popLast(); // shrink trigger
    try expectEqual(4, deque.capacity());

    // 3 1 x x
    // ^ ^--.
    // head tail

    try expectEqual(3, deque.buffer[0]);
    try expectEqual(1, deque.buffer[1]);

    deque.options.init_capacity = 4;

    // test grow ('pushLast') -->

    try deque.pushFirst(4);
    try deque.pushFirst(5);
    try expectEqual(true, deque.isFull());

    // 3 1 5 4
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.capacity());
    try deque.pushLast(6); // growth trigger
    try expectEqual(8, deque.capacity());

    // 5 4 3 1 6 x x x
    // ^       ^
    // head    tail

    try expectEqual(5, deque.peekIndex(0));
    try expectEqual(4, deque.peekIndex(1));
    try expectEqual(3, deque.peekIndex(2));
    try expectEqual(1, deque.peekIndex(3));
    try expectEqual(6, deque.peekIndex(4));

    // test overflow error -->

    deque.options.growable = false;

    try deque.pushLast(7);
    try deque.pushLast(8);
    try deque.pushLast(9);

    try expectError(Error.Overflow, deque.pushLast(10));
}

test "Buffered DoubleEndedQueue" {
    var buffer: [2]u8 = undefined;
    var deque = DoubleEndedQueue(u8).initBuffer(&buffer, .{});

    // test general -->

    try expectEqual(2, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.popFirst());
    try expectError(Error.Underflow, deque.popLast());
    try expectEqual(null, deque.peekFirst());
    try expectEqual(null, deque.peekLast());
    try expectEqual(null, deque.peekIndex(0));

    try deque.pushFirst(1);
    try deque.pushLast(2);

    try expectEqual(2, deque.length());
    try expectEqual(true, deque.isFull());
    try expectError(Error.Overflow, deque.pushFirst(3));
    try expectError(Error.Overflow, deque.pushLast(4));

    try expectEqual(1, deque.peekFirst());
    try expectEqual(2, deque.peekLast());
    try expectEqual(1, deque.peekIndex(0));
    try expectEqual(2, deque.peekIndex(1));

    try expectEqual(1, try deque.popFirst());
    try expectEqual(2, try deque.popLast());

    try expectEqual(true, deque.isEmpty());
}

test "Comptime DoubleEndedQueue" {
    comptime {
        var deque = DoubleEndedQueue(u8).initComptime(.{
            .init_capacity = 2,
            .growable = false,
            .shrinkable = false,
        });

        // test general -->

        try expectEqual(2, deque.capacity());
        try expectEqual(0, deque.length());
        try expectEqual(true, deque.isEmpty());
        try expectError(Error.Underflow, deque.popFirst());
        try expectError(Error.Underflow, deque.popLast());
        try expectEqual(null, deque.peekFirst());
        try expectEqual(null, deque.peekLast());
        try expectEqual(null, deque.peekIndex(0));

        try deque.pushFirst(1);
        try deque.pushLast(2);

        try expectEqual(2, deque.length());
        try expectEqual(true, deque.isFull());
        try expectError(Error.Overflow, deque.pushFirst(3));
        try expectError(Error.Overflow, deque.pushLast(4));

        try expectEqual(1, deque.peekFirst());
        try expectEqual(2, deque.peekLast());
        try expectEqual(1, deque.peekIndex(0));
        try expectEqual(2, deque.peekIndex(1));

        try expectEqual(1, try deque.popFirst());
        try expectEqual(2, try deque.popLast());

        try expectEqual(true, deque.isEmpty());
    }
}
