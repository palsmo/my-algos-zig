//! Author: palsmo
//! Status: In Progress
//! About: Double Ended Queue Data Structure
//! Read: https://en.wikipedia.org/wiki/Double-ended_queue

const std = @import("std");

const maple = @import("maple_utils");

const mod_shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const BufferError = mod_shared.BufferError;
const ExecMode = mod_shared.ExecMode;
const IndexError = mod_shared.IndexError;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;
const assertPowerOf2 = maple.assert.assertPowOf2;
const fastMod = maple.math.fastMod;
const nextPowerOf2 = maple.math.nextPowerOf2;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// A double-ended queue (deque) for items of type `T`.
/// Useful as primitive for other structures.
/// Worse for storing sorted items (has potentially non-contiguous memory layout).
///
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
/// Reference to 'self.buffer' may become invalid after resize routine, use 'self.isValidRef' to verify.
///
/// Properties:
/// Uses 'Circular Array' logic under the hood.
/// Provides efficient operations at buffer endings.
///
///  complexity |     best     |   average    |    worst     |                factor
/// ------------|--------------|--------------|--------------|--------------------------------------
/// insertion   | O(1)         | O(1)         | O(n)         | grow
/// deletion    | O(1)         | O(1)         | O(n)         | shrink
/// lookup      | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|--------------------------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink
/// ------------|--------------|--------------|--------------|--------------------------------------
///  cache loc  | good         | good         | poor         | usage pattern (wrap)
/// ------------------------------------------------------------------------------------------------
pub fn DoubleEndedQueue(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the queue, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the queue can auto grow beyond `init_capacity`
            growable: bool = true,
            // whether the queue can auto shrink when grown past `init_capacity`,
            // size will half when used space falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        // struct fields
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        size: usize = 0,
        options: Options,
        allocator: ?Allocator,
        metadata: u16,

        const meta_msk_is_init: u8 = 0b0000_0000_0000_0001;

        /// Initialize the queue with the active `memory_mode` branch (read more _MemoryMode_).
        ///
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// .Alloc    | fn (allocator: Allocator, comptime options: Options) !Self
        /// .Buffer   | fn (buf: []T, comptime options: Options) Self
        /// .Comptime | fn (comptime options: Options) Self
        /// ----------------------------------------------------------------------------------------
        pub const init = switch (memory_mode) { // * comptime branch prune
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the queue for using heap allocation.
        /// Issue key specs:
        /// - Panic when 'options.init\_capacity' is zero, or not a power of 2.
        /// - Throw error when allocation process fail.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) !Self {
            comptime assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            comptime assertPowerOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
                .metadata = meta_msk_is_init,
            };
        }

        /// Initialize the queue for working with user provided `buf`.
        /// Issue key specs:
        /// - Panic when 'buf.len' is zero, or not a power of 2.
        inline fn initBuffer(buf: []T, comptime options: Options) Self {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});
            assertPowerOf2(buf.len);

            _ = options;

            return .{
                .buffer = buf,
                .options = .{
                    .init_capacity = 0, // * can't set `buf.len`, not comptime guaranteed, doesn't impact flow
                    .growable = false,
                    .shrinkable = false,
                },
                .allocator = null,
                .metadata = meta_msk_is_init,
            };
        }

        /// Initialize the queue for using comptime memory allocation.
        /// Issue key specs:
        /// - Panic when 'options.init\_capacity' is zero, or not a power of 2.
        inline fn initComptime(comptime options: Options) Self {
            assertComptime(@src().fn_name);
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertPowerOf2(options.init_capacity);

            return .{
                .buffer = b: { // * not free-after-use, compiler promotes
                    var buf: [options.init_capacity]T = undefined;
                    break :b &buf;
                },
                .options = options,
                .allocator = null,
                .metadata = meta_msk_is_init,
            };
        }

        /// Release allocated memory, cleanup routine.
        /// Issue key specs:
        /// - Panic when called (only *.Buffer* and *.Comptime* `memory_mode`).
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Buffer, .Comptime => {
                    @compileError("The queue isn't allocated on the heap (remove call 'deinit').");
                },
                .Alloc => {
                    self.assertInit();
                    const ally = self.allocator orelse unreachable;
                    ally.free(self.buffer);
                    self.metaReset();
                },
            }
        }

        /// Assert that `self` has called 'init'.
        /// Issue key specs:
        /// - Panic when `self` hasn't been initialized.
        /// * most often no reason for the user to call.
        pub inline fn assertInit(self: *const Self) void {
            assertAndMsg(self.metaInitStatus(), "DoubleEndedQeueu hasn't been initialized (call 'init' first).", .{});
        }

        /// Reset queue's metadata to zero.
        /// * most often no reason for the user to call.
        pub inline fn metaReset(self: *Self) void {
            self.metadata = 0;
        }

        /// Check queue's init status.
        /// * most often no reason for the user to call.
        pub inline fn metaInitStatus(self: *const Self) bool {
            return meta_msk_is_init == (self.metadata & meta_msk_is_init);
        }

        /// Get current amount of 'T' that's buffered in the queue.
        /// Time - O(1), direct value access.
        pub inline fn capacity(self: *const Self) usize {
            self.assertInit();
            return self.buffer.len;
        }

        /// Get current amount of 'T' that's occupying the queue.
        /// Time - O(1), direct value access.
        pub inline fn length(self: *const Self) usize {
            self.assertInit();
            return self.size;
        }

        /// Check if the queue is empty.
        /// Time - O(1), direct value access.
        pub inline fn isEmpty(self: *const Self) bool {
            self.assertInit();
            return self.size == 0;
        }

        /// Check if the queue is full.
        /// Time - O(1), direct value access.
        pub inline fn isFull(self: *const Self) bool {
            self.assertInit();
            return self.size == self.buffer.len;
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        /// Time - O(1), direct value access.
        pub inline fn isValidRef(self: *const Self, ptr: *const []T) bool {
            self.assertInit();
            return ptr == &self.buffer;
        }

        /// Check if the capacity increase of `amount` would overflow *usize*.
        /// Issue key specs:
        /// - Return-code 0 (ok) or 1 (warn) if overflow.
        /// * most often no reason for the user to call.
        pub inline fn checkCapacityIncrease(self: *const Self, amount: usize) u8 {
            _ = maple.math.safeAdd(usize, self.buffer.len, amount) catch return 1;
            return 0;
        }

        /// Identical to 'pushFirst' but guaranteed to be inlined.
        pub inline fn pushFirstInline(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            try @call(.always_inline, pushFirst, .{ self, item, exec_mode });
        }

        /// Store an `item` first in the queue.
        /// Time - O(1)/O(n), wrap decrement to new slot, may grow.
        /// Issue key specs:
        /// - Throw error when adding at max capacity with 'self.options.growable' set to false.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        /// Other:
        /// - User has manual control over the 'grow' routine (only *.Uncheck* `exec_mode`).
        pub fn pushFirst(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            // setup?
            switch (exec_mode) { // * comptime branch prune
                .Uncheck => {},
                .Safe => {
                    self.assertInit();
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            // grow?
            switch (exec_mode) { // * comptime branch prune
                .Uncheck => {},
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

            // update 'head' position
            switch (self.size != 0) {
                true => self.head = wrapDecrement(usize, self.head, 0, self.buffer.len),
                false => {}, // * skip decrement, 'head' already points to valid slot
            }

            // add item and update size
            self.buffer[self.head] = item;
            self.size += 1;
        }

        /// Store all `items` first in the queue.
        /// Time - O(1)/O(n), may grow.
        /// Issue key specs:
        /// - Throw error when new capacity would overflow *usize*.
        /// - Throw error when queue hasn't enough capacity with 'self.options.growable' set to false.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        pub fn pushFirstBatch(self: *Self, items: []const T, exec_mode: ExecMode) !void {
            // setup?
            switch (exec_mode) { // * comptime branch prune
                .Uncheck => {},
                .Safe => {
                    self.assertInit();
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            if (items.len == 0) return;
            const required_capacity = try maple.math.safeAdd(usize, self.size, items.len);

            // grow?
            if (required_capacity > self.buffer.len) {
                switch (memory_mode) { // * comptime branch prune
                    .Buffer => return BufferError.NotEnoughSpace,
                    .Alloc, .Comptime => switch (self.options.growable) {
                        false => return BufferError.NotEnoughSpace,
                        true => {
                            const n = required_capacity / (self.buffer.len + 1); // * avoid extra grow routine when same
                            const m = nextPowerOf2(n);
                            try self.resize(self.buffer.len * m, .Before);
                        },
                    },
                }
            }

            // TODO, copy elements correct way!

            // update start 'head' position
            switch (self.size != 0) {
                true => self.head = wrapDecrement(usize, self.head, 0, self.buffer.len),
                false => {}, // * skip increment, 'head' already points to valid slot
            }

            // add items (last in special to avoid extra increment)
            const last_i = items.len - 1;
            for (0..last_i) |i| {
                self.buffer[self.head] = items[i];
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            }
            self.buffer[self.head] = items[last_i];

            self.size = required_capacity;
        }

        /// Identical to 'pushLast' but guaranteed to be inlined.
        pub inline fn pushLastInline(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            try @call(.always_inline, pushLast, .{ self, item, exec_mode });
        }

        /// Store an `item` last in the queue.
        /// Time - O(1)/O(n), wrap increment to new slot, may grow.
        /// Issue key specs:
        /// - Throw error when adding at max capacity with 'self.options.growable' set to false.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        /// Other:
        /// - User has manual control over the 'grow' routine (only *.Uncheck* `exec_mode`).
        pub fn pushLast(self: *Self, item: T, comptime exec_mode: ExecMode) !void {
            // setup?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    self.assertInit();
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            // grow?
            switch (exec_mode) {
                .Uncheck => {},
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

            // update 'tail' position
            switch (self.size != 0) {
                true => self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len),
                false => {}, // * skip increment, 'tail' already points to valid slot
            }

            // add item and update size
            self.buffer[self.tail] = item;
            self.size += 1;
        }

        /// Store all `items` last in the queue.
        /// Time - O(1)/O(n).
        /// Issue key specs:
        /// - Throw error when required capacity would overflow *usize*.
        /// - Throw error when queue hasn't enough capacity with 'self.options.growable' set to false.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        pub fn pushLastBatch(self: *Self, items: []const T, exec_mode: ExecMode) !void {
            // setup?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            if (items.len == 0) return;
            const required_capacity = try maple.math.safeAdd(usize, self.size, items.len);

            // grow?
            if (required_capacity > self.buffer.len) {
                switch (memory_mode) {
                    .Buffer => return BufferError.NotEnoughSpace,
                    .Alloc, .Comptime => switch (self.options.growable) {
                        false => return BufferError.NotEnoughSpace,
                        true => {
                            // calc how many times to double/grow the size
                            var n = required_capacity / (self.buffer.len + 1); // * avoids extra grow routines when same
                            while (n > 0) : (n -= 1) try self.grow();
                        },
                    },
                }
            }

            // update start 'tail' position
            switch (self.size != 0) {
                true => self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len),
                false => {}, // * skip increment, 'tail' already points to valid slot
            }

            // add items (last is special to avoid extra increment)
            const last_i = items.len - 1;
            for (0..last_i) |i| {
                self.buffer[self.tail] = items[i];
                self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len);
            }
            self.buffer[self.tail] = items[last_i];

            self.size = required_capacity;
        }

        /// Identical to 'popFirst' but guaranteed to be inlined.
        pub inline fn popFirstInline(self: *Self, comptime exec_mode: ExecMode) ?T {
            return try @call(.always_inline, popFirst, .{ self, exec_mode });
        }

        /// Get the first item in the queue, free its memory.
        /// Time - O(1)/O(n), wrap increment to prev slot, may shrink.
        /// Issue key specs:
        /// - Undefined behavior when queue is empty (only *.Uncheck* `exec_mode`).
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        /// Other:
        /// - User has manual control over the 'shrink' routine (only *.Uncheck* `exec_mode`).
        pub fn popFirst(self: *Self, comptime exec_mode: ExecMode) ?T {
            // setup?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            // empty?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => if (self.size == 0) return null,
            }

            const item = self.buffer[self.head];

            // update head position
            if (self.size > 1) {
                self.head = wrapIncrement(usize, self.head, 0, self.buffer.len);
            } else {} // * skip increment, `head` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (exec_mode) {
                .Uncheck => {},
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

            return item;
        }

        /// Identical to 'popLast' but guaranteed to be inlined.
        pub inline fn popLastInline(self: *Self, comptime exec_mode: ExecMode) ?T {
            return try @call(.always_inline, popLast, .{ self, exec_mode });
        }

        /// Get the last item in the queue, free its memory.
        /// Time - O(1)/O(n), wrap decrement to prev slot, may shrink.
        /// Issue key specs:
        /// - Undefined behavior when queue is empty (only *.Uncheck* `exec_mode`).
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        /// Other:
        /// - User has manual control over the 'shrink' routine (only *.Uncheck* `exec_mode`).
        pub fn popLast(self: *Self, comptime exec_mode: ExecMode) ?T {
            // setup?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                },
            }

            // empty?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => if (self.size == 0) return null,
            }

            const item = self.buffer[self.tail];

            // update tail position
            if (self.size > 1) {
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            } else {} // * skip decrement, `tail` already points to valid slot

            self.size -= 1;

            // shrink?
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => switch (memory_mode) {
                    .Buffer => {},
                    .Alloc, .Comptime => switch (self.options.shrinkable) {
                        false => {},
                        true => if (self.size >= self.options.init_capacity and self.size <= self.buffer.len / 4) {
                            try self.shrink();
                        },
                    },
                },
            }

            return item;
        }

        /// Identical to 'peekFirst' but guaranteed to be inlined.
        pub inline fn peekFirstInline(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, peekFirst, .{ self, exec_mode });
        }

        /// Get the first item in the queue.
        /// Time - O(1), direct indexing.
        /// Other:
        /// - Undefined behavior when queue is empty (only *.Uncheck* `exec_mode`).
        pub fn peekFirst(self: *const Self, comptime exec_mode: ExecMode) ?T {
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                    if (self.size == 0) return null;
                },
            }
            return self.buffer[self.head];
        }

        /// Identical to 'peekLast' but guaranteed to be inlined.
        pub inline fn peekLastInline(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, peekLast, .{ self, exec_mode });
        }

        /// Get the last item in the queue.
        /// Time - O(1), direct indexing.
        /// Issue key specs:
        /// - Undefined behavior when queue is empty (only *.Uncheck* `exec_mode`).
        pub fn peekLast(self: *const Self, comptime exec_mode: ExecMode) ?T {
            switch (exec_mode) {
                .Uncheck => {},
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                    if (self.size != 0) {} else return null;
                },
            }
            return self.buffer[self.tail];
        }

        /// Identical to 'peekIndex' but guaranteed to be inlined.
        pub inline fn peekIndexInline(self: *const Self, index: usize, comptime exec_mode: ExecMode) !T {
            return @call(.always_inline, peekIndex, .{ self, index, exec_mode });
        }

        /// Get an item at index `index` in the queue.
        /// Time - O(1), calc direct indexing.
        /// Issue key specs:
        /// - Throws error when `index` is out of bounds of 'self.length()' (only *.Safe* `exec_mode`).
        pub fn peekIndex(self: *const Self, index: usize, comptime exec_mode: ExecMode) !T {
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => {
                    assertAndMsg(self.is_initialized, "DoubleEndedQueue hasn't been initialized (call 'init').", .{});
                    if (memory_mode == .Comptime) assertComptime(@src().fn_name);
                    if (index > self.size) return IndexError.OutOfBounds;
                },
            }
            const sum = self.head +% index;
            const actual_index = fastMod(usize, sum, self.buffer.len);
            return self.buffer[actual_index];
        }

        /// Load content of `buf` into list at `side`.
        /// Time - O(n).
        /// Issue keys specs:
        /// - Throw error when required capacity would overflow *usize*.
        /// - Throw error when queue hasn't enough capacity with 'self.options.growable' *false*.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
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

        /// Reset the queue to its empty initial state.
        /// Time - O(1), fixed writes, may memory release + memory alloc.
        /// Issue key specs:
        /// - Throws error when allocation process fail (only *.Alloc* `memory_mode`).
        pub fn reset(self: *Self) !void {
            // may allocate new buffer with 'self.init_capacity'
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
                .Comptime => { // * not free-after-use, compiler promotes
                    assertComptime(@src().fn_name);
                    if (self.buffer.len != self.options.init_capacity) {
                        // allocate new buffer with 'self.init_capacity'
                        // * not free-after-use, compiler promotes
                        var buf: [self.options.init_capacity]T = undefined;
                        self.buffer = &buf;
                    }
                },
            }

            self.head = 0;
            self.tail = 0;
            self.size = 0;
        }

        /// Copy over current content into new buffer of **twice** the size.
        /// Time - O(n), clone content.
        /// Issue key specs:
        /// - Throw error when new capacity would overflow *usize*.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        pub fn grow(self: *Self) !void {
            const new_capacity = try maple.math.safeMul(usize, self.buffer.len, 2);
            try self.resize(new_capacity, .After);
        }

        /// Copy over current content into new buffer of **half** the size.
        /// Time - O(n), clone content.
        /// Issue key specs:
        /// - Throw error when new capacity wouldn't fit all content in queue.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        pub fn shrink(self: *Self) !void {
            const new_capacity = self.buffer.len / 2;
            try self.resize(new_capacity, .After);
        }

        /// Copy over current content into new buffer of size `new_capacity`.
        /// Time - O(n), clone content.
        /// Issue key specs:
        /// - Throw error when `new_capacity` wouldn't fit all content in queue.
        /// - Throw error when resize heap allocation fail (only *.Alloc* `memory_mode`).
        pub fn resize(self: *Self, new_capacity: usize, comptime side: enum { Before, After }) !void {
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

            switch (side) {
                .After => {
                    if (self.head <= self.tail) {
                        // * `tail` is not wrapped around
                        // copy over whole buffer
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
                },
                .Before => {
                    const start_index_new_mem = new_buffer.len - self.size;
                    if (self.head <= self.tail) {
                        // * `tail` is not wrapped around
                        // copy over whole buffer
                        const old_mem = self.buffer[self.head .. self.tail + 1];
                        const new_mem = new_buffer[start_index_new_mem..new_buffer.len];
                        @memcpy(new_mem, old_mem);
                    } else {
                        // * `head` or/and `tail` is wrapped around
                        // copy over first part
                        const old_mem_a = self.buffer[self.head..self.buffer.len];
                        const new_mem_a = new_buffer[start_index_new_mem..];
                        @memcpy(new_mem_a, old_mem_a);
                        // copy over second part
                        const old_mem_b = self.buffer[0 .. self.tail + 1];
                        const new_mem_b = new_buffer[start_index_new_mem + old_mem_a.len ..];
                        @memcpy(new_mem_b, old_mem_b);
                    }
                },
            }

            if (memory_mode == .Alloc) {
                const ally = self.allocator orelse unreachable;
                ally.free(self.buffer);
            }

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

test "Comptime DoubleEndedQueue" {
    comptime {
        const T_deque = DoubleEndedQueue(u8, .Comptime);
        var deque: T_deque = T_deque.init(.{
            .init_capacity = 4,
            .growable = true,
            .shrinkable = true,
        });

        // test empty state -->

        try expectEqual(4, deque.capacity());
        try expectEqual(0, deque.length());
        try expectEqual(true, deque.isEmpty());
        try expectError(BufferError.Underflow, deque.popFirst(.Safe));
        try expectError(BufferError.Underflow, deque.popLast(.Safe));
        try expectEqual(null, deque.peekFirst(.Safe));
        try expectEqual(null, deque.peekLast(.Safe));
        try expectEqual(null, deque.peekIndex(0, .Safe));

        // test basic push and pop -->

        try deque.pushFirst(1, .Safe);
        try deque.pushLast(2, .Safe);
        try expectEqual(2, deque.length());
        try expectEqual(1, deque.popFirst(.Safe));
        try expectEqual(2, deque.popLast(.Safe));

        // x x x x
        //   ^.---.
        //   tail head

        try expectEqual(true, deque.head == deque.tail);
        try expectEqual(true, deque.isEmpty());

        try deque.reset();

        // test wrapping behavior -->

        try deque.pushLastBatch(&.{ 1, 2, 3, 4 });
        _ = try deque.popFirst(.Safe);
        try deque.pushLast(5, .Safe);

        // 5 2 3 4
        // ^ ^--.
        // tail head

        try expectEqual(0, deque.tail); // tail wrap

        _ = try deque.popLast(.Safe);
        _ = try deque.popLast(.Safe);
        try deque.pushFirstBatch(&.{ 5, 4 });
        //try deque.pushFirst(4, .Safe);
        //try deque.pushFirst(5, .Safe);

        // 4 2 3 5
        //     ^ ^--.
        //     tail head

        try expectEqual(3, deque.head); // head wrap

        // test shrink ('popFirst') -->

        deque.options.init_capacity = 8;
        try deque.reset();
        deque.options.init_capacity = 2;

        try deque.pushFirst(1, .Safe);
        try deque.pushLast(2, .Safe);
        try deque.pushFirst(3, .Safe);

        // 2 x x x x x 3 1
        // ^           ^
        // tail        head

        try expectEqual(8, deque.capacity());
        _ = try deque.popFirst(.Safe); // shrink trigger
        try expectEqual(4, deque.capacity());

        // 1 2 x x
        // ^ ^--.
        // head tail

        try expectEqual(1, deque.peekIndex(0, .Safe));
        try expectEqual(2, deque.peekIndex(1, .Safe));
        try expectEqual(null, deque.peekIndex(2, .Safe));

        // test grow ('pushFirst') -->

        try deque.pushFirst(3, .Safe);
        try deque.pushFirst(4, .Safe);
        try expectEqual(true, deque.isFull());

        // 1 2 4 3
        //   ^ ^--.
        //   tail head

        try expectEqual(4, deque.capacity());
        try deque.pushFirst(5, .Safe); // growth trigger
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

        _ = try deque.popFirst(.Safe);
        _ = try deque.popFirst(.Safe);

        // x x 3 1 2 x x x
        //     ^   ^.
        //     head tail

        deque.options.init_capacity = 2;

        try expectEqual(8, deque.capacity());
        _ = try deque.popLast(.Safe); // shrink trigger
        try expectEqual(4, deque.capacity());

        // 3 1 x x
        // ^ ^--.
        // head tail

        try expectEqual(3, deque.buffer[0]);
        try expectEqual(1, deque.buffer[1]);

        deque.options.init_capacity = 4;

        // test grow ('pushLast') -->

        try deque.pushFirst(4, .Safe);
        try deque.pushFirst(5, .Safe);
        try expectEqual(true, deque.isFull());

        // 3 1 5 4
        //   ^ ^--.
        //   tail head

        try expectEqual(4, deque.capacity());
        try deque.pushLast(6, .Safe); // growth trigger
        try expectEqual(8, deque.capacity());

        // 5 4 3 1 6 x x x
        // ^       ^
        // head    tail

        try expectEqual(5, deque.peekIndex(0, .Safe));
        try expectEqual(4, deque.peekIndex(1, .Safe));
        try expectEqual(3, deque.peekIndex(2, .Safe));
        try expectEqual(1, deque.peekIndex(3, .Safe));
        try expectEqual(6, deque.peekIndex(4, .Safe));

        // test overflow error -->

        deque.options.growable = false;

        try deque.pushLast(7, .Safe);
        try deque.pushLast(8, .Safe);
        try deque.pushLast(9, .Safe);

        try expectError(BufferError.Overflow, deque.pushLast(10, .Safe));
    }
}

test "Allocated DoubleEndedQueue" {
    const allocator = std.testing.allocator;
    const T_deque = DoubleEndedQueue(u8, .Alloc);
    var deque: T_deque = try T_deque.init(allocator, .{
        .init_capacity = 2,
        .growable = false,
        .shrinkable = false,
    });

    defer deque.deinit();

    // test general -->

    try expectEqual(2, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(BufferError.Underflow, deque.popFirst(.Safe));
    try expectError(BufferError.Underflow, deque.popLast(.Safe));
    try expectEqual(null, deque.peekFirst(.Safe));
    try expectEqual(null, deque.peekLast(.Safe));
    try expectEqual(null, deque.peekIndex(0, .Safe));

    try deque.pushFirst(1, .Safe);
    try deque.pushLast(2, .Safe);

    try expectEqual(2, deque.length());
    try expectEqual(true, deque.isFull());
    try expectError(BufferError.Overflow, deque.pushFirst(3, .Safe));
    try expectError(BufferError.Overflow, deque.pushLast(4, .Safe));

    try expectEqual(1, deque.peekFirst(.Safe));
    try expectEqual(2, deque.peekLast(.Safe));
    try expectEqual(1, deque.peekIndex(0, .Safe));
    try expectEqual(2, deque.peekIndex(1, .Safe));

    try expectEqual(1, deque.popFirst(.Safe));
    try expectEqual(2, deque.popLast(.Safe));

    try expectEqual(true, deque.isEmpty());
}

test "Buffered DoubleEndedQueue" {
    var buffer: [2]u8 = undefined;
    const T_deque = DoubleEndedQueue(u8, .Buffer);
    var deque: T_deque = T_deque.init(&buffer, .{});

    // test general -->

    try expectEqual(2, deque.capacity());
    try expectEqual(0, deque.length());
    try expectEqual(true, deque.isEmpty());
    try expectError(BufferError.Underflow, deque.popFirst(.Safe));
    try expectError(BufferError.Underflow, deque.popLast(.Safe));
    try expectEqual(null, deque.peekFirst(.Safe));
    try expectEqual(null, deque.peekLast(.Safe));
    try expectEqual(null, deque.peekIndex(0, .Safe));

    try deque.pushFirst(1, .Safe);
    try deque.pushLast(2, .Safe);

    try expectEqual(2, deque.length());
    try expectEqual(true, deque.isFull());
    try expectError(BufferError.Overflow, deque.pushFirst(3, .Safe));
    try expectError(BufferError.Overflow, deque.pushLast(4, .Safe));

    try expectEqual(1, deque.peekFirst(.Safe));
    try expectEqual(2, deque.peekLast(.Safe));
    try expectEqual(1, deque.peekIndex(0, .Safe));
    try expectEqual(2, deque.peekIndex(1, .Safe));

    try expectEqual(1, deque.popFirst(.Safe));
    try expectEqual(2, deque.popLast(.Safe));

    try expectEqual(true, deque.isEmpty());
}
