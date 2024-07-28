//! Author: palsmo
//! Status: Done
//! About: Double-Ended Queue Data Structure
//! Read: https://en.wikipedia.org/wiki/Double-ended_queue

const std = @import("std");

const maple = @import("maple_utils");

const root_shared = @import("./shared.zig");
const shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const Error = root_shared.Error;
const MemoryMode = shared.MemoryMode;
const assertAndMsg = maple.debug.assertAndMsg;
const assertComptime = maple.debug.assertComptime;
const assertPowOf2 = maple.math.assertPowOf2;
const panic = std.debug.panic;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// A double-ended queue (deque) for items of type `T`.
/// Provides efficient insertion, removal and lookup operations at both ends.
/// Useful as primitive for other structures.
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
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
pub fn DoubleEndedQueue(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
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
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the queue depending on `memory_mode` (read more _MemoryMode_ docs).
        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the queue for using heap allocation.
        fn initAlloc(allocator: Allocator, options: Options) !Self {
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue for working with user provided `buf`.
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

        /// Initialize the queue for using comptime memory allocation.
        fn initComptime(comptime options: Options) Self {
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
                    const msg = "The queue is not allocated on the heap, remove unnecessary call 'deinit'";
                    if (@inComptime()) @compileError(msg) else panic(msg, .{});
                },
            }
        }

        /// Identical to 'pushFirst' but guaranteed to be inlined.
        pub inline fn pushFirstInline(self: *Self, item: T, issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!void,
            .Panic => void,
        } {
            try @call(.always_inline, pushFirst, .{ self, item, issue_mode });
        }

        /// Store an `item` first in the queue.
        /// Decide with `issue_mode` to handle errors normally or panic when error is possible.
        /// Throws error when adding at max capacity with 'self.options.growable' set to false,
        /// or as part of an allocation process (grow).
        pub fn pushFirst(self: *Self, item: T, comptime issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!void,
            .Panic => void,
        } {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            if (self.size < self.buffer.len) {} else {
                switch (issue_mode) {
                    .Error => switch (memory_mode) {
                        .Alloc, .Comptime => if (self.options.growable) try self.grow() else return Error.Overflow,
                        .Buffer => return Error.Overflow,
                    },
                    .Panic => panic("Could possibly throw an unhandled error.", .{}),
                }
            }

            if (self.size != 0) {
                self.head = wrapDecrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip decrement, `head` already points to valid slot

            self.buffer[self.head] = item;
            self.size += 1;
        }

        /// Identical to 'pushLast' but guaranteed to be inlined.
        pub inline fn pushLastInline(self: *Self, item: T, issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!void,
            .Panic => void,
        } {
            try @call(.always_inline, pushLast, .{ self, item, issue_mode });
        }

        /// Store an `item` last in the queue.
        /// Decide with `issue_mode` to handle errors normally or panic when error is possible.
        /// Throws error when adding at max capacity with 'self.options.growable' set to false,
        /// or as part of an allocation process (grow).
        pub fn pushLast(self: *Self, item: T, comptime issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!void,
            .Panic => void,
        } {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            if (self.size < self.buffer.len) {} else {
                switch (issue_mode) {
                    .Error => switch (memory_mode) {
                        .Alloc, .Comptime => if (self.options.growable) try self.grow() else return Error.Overflow,
                        .Buffer => return Error.Overflow,
                    },
                    .Panic => panic("Could possibly throw an unhandled error.", .{}),
                }
            }

            if (self.size != 0) {
                self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip increment, `tail` already points to valid slot

            self.buffer[self.tail] = item;
            self.size += 1;
        }

        /// Identical to 'popFirst' but guaranteed to be inlined.
        pub inline fn popFirstInline(self: *Self, issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!T,
            .Panic => T,
        } {
            return try @call(.always_inline, popFirst, .{self});
        }

        /// Get the first item in the queue, free its memory.
        /// Throws error when trying to release from empty queue, or as part of an allocation process (shrink).
        pub fn popFirst(self: *Self, comptime issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!T,
            .Panic => T,
        } {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            if (self.size != 0) {} else {
                switch (issue_mode) {
                    .Error => return Error.Underflow,
                    .Panic => panic("Tried to release value from empty queue.", .{}),
                }
            }

            const item = self.buffer[self.head];
            if (self.size > 1) {
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip increment, `head` already points to valid slot

            self.size -= 1;

            switch (memory_mode) {
                .Alloc, .Comptime => {
                    if (self.options.shrinkable and
                        self.size >= self.options.init_capacity and
                        self.size <= self.buffer.len / 4)
                    {
                        switch (issue_mode) {
                            .Error => try self.shrink(),
                            .Panic => panic("Could possibly throw an unhandled error.", .{}),
                        }
                    }
                },
                .Buffer => {},
            }

            return item;
        }

        /// Identical to 'popLast' but guaranteed to be inlined.
        pub inline fn popLastInline(self: *Self, issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!T,
            .Panic => T,
        } {
            return try @call(.always_inline, popLast, .{self});
        }

        /// Get the last item in the queue, free its memory.
        /// Get the first item in the queue, free its memory.
        /// Throws error when trying to release from empty queue, or as part of an allocation process (shrink).
        pub fn popLast(self: *Self, comptime issue_mode: enum { Error, Panic }) switch (issue_mode) {
            .Error => anyerror!T,
            .Panic => T,
        } {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            if (self.size != 0) {} else {
                switch (issue_mode) {
                    .Error => return Error.Underflow,
                    .Panic => panic("Tried to release value from empty queue.", .{}),
                }
            }

            const item = self.buffer[self.tail];
            if (self.size > 1) {
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip decrement, `tail` already points to valid slot

            self.size -= 1;

            switch (memory_mode) {
                .Alloc, .Comptime => {
                    if (self.options.shrinkable and
                        self.size >= self.options.init_capacity and
                        self.size <= self.buffer.len / 4)
                    {
                        switch (issue_mode) {
                            .Error => try self.shrink(),
                            .Panic => panic("Could possibly throw an unhandled error.", .{}),
                        }
                    }
                },
                .Buffer => {},
            }

            return item;
        }

        /// Identical to 'peekFirst' but guaranteed to be inlined.
        pub inline fn peekFirstInline(self: *const Self) ?T {
            return @call(.always_inline, peekFirst, .{self});
        }

        /// Get the first item in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekFirst(self: *const Self) ?T {
            if (self.size != 0) {} else return null;
            return self.buffer[self.head];
        }

        /// Identical to 'peekLast' but guaranteed to be inlined.
        pub inline fn peekLastInline(self: *const Self) ?T {
            return @call(.always_inline, peekLast, .{self});
        }

        /// Get the last item in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekLast(self: *const Self) ?T {
            if (self.size != 0) {} else return null;
            return self.buffer[self.tail];
        }

        /// Identical to 'peekIndex' but guaranteed to be inlined.
        pub inline fn peekIndexInline(self: *const Self) ?T {
            return @call(.always_inline, peekIndex, .{self});
        }

        /// Get an item at index `index` in the queue.
        /// Returns _null_ only if there's no value.
        pub fn peekIndex(self: *const Self, index: usize) ?T {
            if (self.size > index) {} else return null;
            const sum = self.head +% index;
            const actual_index = sum % self.buffer.len;
            return self.buffer[actual_index];
        }

        /// Get current amount of 'T' that's buffered in the queue.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Get current amount of 'T' that's occupying the queue.
        pub inline fn length(self: *const Self) usize {
            return self.size;
        }

        /// Reset queue to its empty state.
        /// Throws error as part of an allocation process.
        pub fn reset(self: *Self) !void {
            // allocate new buffer with initial capacity
            if (self.buffer.len != self.options.init_capacity) {
                switch (memory_mode) {
                    .Alloc => {
                        self.allocator.?.free(self.buffer);
                        self.buffer = try self.allocator.?.alloc(T, self.options.init_capacity);
                    },
                    .Comptime => { // * not 'free-after-use', compiler promotes
                        assertComptime(@src().fn_name);
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
        pub inline fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }

        /// Check if the queue is full.
        /// Returns _true_ (full) or _false_ (not full).
        pub inline fn isFull(self: *const Self) bool {
            return self.size == self.buffer.len;
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        /// Returns _true_ (valid ref) or _false_ (invalid ref).
        pub inline fn isValidRef(self: *const Self, ptr: *[]T) bool {
            return ptr == &self.buffer;
        }

        /// Copy over current content into new buffer of twice the size.
        /// Throws error as part of an allocation process.
        fn grow(self: *Self) !void {
            // allocate new buffer with more capacity
            const new_capacity = try std.math.mul(usize, self.buffer.len, 2);
            const new_buffer = switch (memory_mode) {
                .Alloc => try self.allocator.?.alloc(T, new_capacity),
                .Buffer => unreachable,
                .Comptime => b: { // * not 'free-after-use', compiler promotes
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

            if (memory_mode == .Alloc) self.allocator.?.free(self.buffer);

            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.size - 1;
        }

        /// Copy over current content into a new buffer of half the size.
        /// Throws error as part of an allocation process.
        fn shrink(self: *Self) !void {
            // allocate new buffer with less capacity
            const new_capacity = try std.math.divExact(usize, self.buffer.len, 2);
            const new_buffer = switch (memory_mode) {
                .Alloc => try self.allocator.?.alloc(T, new_capacity),
                .Comptime => b: { // * not 'free-after-use', compiler promotes
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

            if (memory_mode == .Alloc) self.allocator.?.free(self.buffer);

            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.size - 1;
        }

        inline fn mayGrowOrThrow(self: *Self) !void {
            switch (memory_mode) {
                .Alloc, .Comptime => if (self.options.growable) try self.grow() else return Error.Overflow,
                .Buffer => return Error.Overflow,
            }
        }

        inline fn mayShrinkOrThrow(self: *Self) !void {
            if (self.size >= self.options.init_capacity) {
                if (self.size > self.buffer.len / 4) {} else try self.shrink();
            }
        }
    };
}

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "Allocated DoubleEndedQueue" {
    const allocator = std.testing.allocator;
    var deque = try DoubleEndedQueue(u8, .Alloc).init(allocator, .{
        .init_capacity = 4,
        .growable = true,
        .shrinkable = true,
    });
    defer deque.deinit();

    // test empty state -->

    try expectEqual(4, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.popFirst(.Error));
    try expectError(Error.Underflow, deque.popLast(.Error));
    try expectEqual(null, deque.peekFirst());
    try expectEqual(null, deque.peekLast());
    try expectEqual(null, deque.peekIndex(0));

    // test basic push and pop -->

    deque.pushFirst(1, .Panic);
    deque.pushLast(2, .Panic);
    try expectEqual(2, deque.length());
    try expectEqual(1, deque.popFirst(.Panic));
    try expectEqual(2, deque.popLast(.Panic));

    // x x x x
    //   ^.---.
    //   tail head

    try expectEqual(true, deque.head == deque.tail);
    try expectEqual(true, deque.isEmpty());

    try deque.reset();

    // test wrapping behavior -->

    deque.pushLast(1, .Panic);
    deque.pushLast(2, .Panic);
    deque.pushLast(3, .Panic);
    deque.pushLast(4, .Panic);
    _ = deque.popFirst(.Panic);
    deque.pushLast(5, .Panic);

    // 5 2 3 4
    // ^ ^--.
    // tail head

    try expectEqual(0, deque.tail); // tail wrap

    _ = deque.popLast(.Panic);
    _ = deque.popLast(.Panic);
    deque.pushFirst(4, .Panic);
    deque.pushFirst(5, .Panic);

    // 4 2 3 5
    //     ^ ^--.
    //     tail head

    try expectEqual(3, deque.head); // head wrap

    // test shrink ('popFirst') -->

    deque.options.init_capacity = 8;
    try deque.reset();
    deque.options.init_capacity = 2;

    deque.pushFirst(1, .Panic);
    deque.pushLast(2, .Panic);
    deque.pushFirst(3, .Panic);

    // 2 x x x x x 3 1
    // ^           ^
    // tail        head

    try expectEqual(8, deque.capacity());
    _ = try deque.popFirst(.Error); // shrink trigger
    try expectEqual(4, deque.capacity());

    // 1 2 x x
    // ^ ^--.
    // head tail

    try expectEqual(1, deque.peekIndex(0));
    try expectEqual(2, deque.peekIndex(1));
    try expectEqual(null, deque.peekIndex(2));

    // test grow ('pushFirst') -->

    deque.pushFirst(3, .Panic);
    deque.pushFirst(4, .Panic);
    try expectEqual(true, deque.isFull());

    // 1 2 4 3
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.capacity());
    try deque.pushFirst(5, .Error); // growth trigger
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

    _ = deque.popFirst(.Panic);
    _ = deque.popFirst(.Panic);

    // x x 3 1 2 x x x
    //     ^   ^.
    //     head tail

    deque.options.init_capacity = 2;

    try expectEqual(8, deque.capacity());
    _ = try deque.popLast(.Error); // shrink trigger
    try expectEqual(4, deque.capacity());

    // 3 1 x x
    // ^ ^--.
    // head tail

    try expectEqual(3, deque.buffer[0]);
    try expectEqual(1, deque.buffer[1]);

    deque.options.init_capacity = 4;

    // test grow ('pushLast') -->

    deque.pushFirst(4, .Panic);
    deque.pushFirst(5, .Panic);
    try expectEqual(true, deque.isFull());

    // 3 1 5 4
    //   ^ ^--.
    //   tail head

    try expectEqual(4, deque.capacity());
    try deque.pushLast(6, .Error); // growth trigger
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

    deque.pushLast(7, .Panic);
    deque.pushLast(8, .Panic);
    deque.pushLast(9, .Panic);

    try expectError(Error.Overflow, deque.pushLast(10, .Error));
}

test "Buffered DoubleEndedQueue" {
    var buffer: [2]u8 = undefined;
    var deque = DoubleEndedQueue(u8, .Buffer).init(&buffer, .{});

    // test general -->

    try expectEqual(2, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(Error.Underflow, deque.popFirst(.Error));
    try expectError(Error.Underflow, deque.popLast(.Error));
    try expectEqual(null, deque.peekFirst());
    try expectEqual(null, deque.peekLast());
    try expectEqual(null, deque.peekIndex(0));

    deque.pushFirst(1, .Panic);
    deque.pushLast(2, .Panic);

    try expectEqual(2, deque.length());
    try expectEqual(true, deque.isFull());
    try expectError(Error.Overflow, deque.pushFirst(3, .Error));
    try expectError(Error.Overflow, deque.pushLast(4, .Error));

    try expectEqual(1, deque.peekFirst());
    try expectEqual(2, deque.peekLast());
    try expectEqual(1, deque.peekIndex(0));
    try expectEqual(2, deque.peekIndex(1));

    try expectEqual(1, deque.popFirst(.Panic));
    try expectEqual(2, deque.popLast(.Panic));

    try expectEqual(true, deque.isEmpty());
}

test "Comptime DoubleEndedQueue" {
    comptime {
        var deque = DoubleEndedQueue(u8, .Comptime).init(.{
            .init_capacity = 2,
            .growable = false,
            .shrinkable = false,
        });

        // test general -->

        try expectEqual(2, deque.capacity());
        try expectEqual(0, deque.length());
        try expectEqual(true, deque.isEmpty());
        try expectError(Error.Underflow, deque.popFirst(.Error));
        try expectError(Error.Underflow, deque.popLast(.Error));
        try expectEqual(null, deque.peekFirst());
        try expectEqual(null, deque.peekLast());
        try expectEqual(null, deque.peekIndex(0));

        deque.pushFirst(1, .Panic);
        deque.pushLast(2, .Panic);

        try expectEqual(2, deque.length());
        try expectEqual(true, deque.isFull());
        try expectError(Error.Overflow, deque.pushFirst(3, .Error));
        try expectError(Error.Overflow, deque.pushLast(4, .Error));

        try expectEqual(1, deque.peekFirst());
        try expectEqual(2, deque.peekLast());
        try expectEqual(1, deque.peekIndex(0));
        try expectEqual(2, deque.peekIndex(1));

        try expectEqual(1, deque.popFirst(.Panic));
        try expectEqual(2, deque.popLast(.Panic));

        try expectEqual(true, deque.isEmpty());
    }
}
