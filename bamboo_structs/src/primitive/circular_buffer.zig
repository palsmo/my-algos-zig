//! Author: palsmo
//! Status: In Progress
//! Brief: Double Ended Queue Data Structure
//! Read: https://en.wikipedia.org/wiki/Circular_buffer

const std = @import("std");

const prj = @import("project");
const maple = @import("maple_utils");

const Allocator = std.mem.Allocator;
const BufferError = prj.errors.BufferError;
const ExecMode = prj.modes.ExecMode;
const IndexError = prj.errors.IndexError;
const MemoryMode = prj.modes.MemoryMode;
const ValueError = prj.errors.ValueError;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;
const assertPowerOf2 = maple.assert.assertPowerOf2;
const fastMod = maple.math.int.fastMod;
const checkedAdd = maple.math.int.checkedAdd;
const checkedMul = maple.math.int.checkedMul;
const nextPowerOf2 = maple.math.misc.nextPowerOf2;
const wrapDecrement = maple.math.misc.wrapDecrement;
const wrapIncrement = maple.math.misc.wrapIncrement;

/// A circular buffer for items of type `T`.
/// Useful as primitive for other structures (deque, fifo-queue, stack etc.)
/// Not optimal for sorted items (has potentially non-contiguous memory layout).
///
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
/// Reference to `self.buffer` may become invalid after resize routine, verify with `self.isValidRef`.
///
/// Properties:
/// - Provides efficient operations at buffer endings.
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
///
/// Functions:
///
/// init = initAlloc or initBuffer or initComptime
///
/// deinit() void
/// assertInit() void
/// metaReset() void
/// metaInitStatus() bool
/// capacity() usize
/// size() usize
/// isEmpty() bool
/// isFull() bool
/// isValidRef(ptr: *const []T) bool
/// checkCapacityIncrease(amount: usize) u8
///
/// pushFirst(item: T, exec_mode: ExecMode) void / !void
/// pushFirstInline(item: T, exec_mode: ExecMode) void / !void
/// pushFirstBatch(items: []const T, exec_mode: ExecMode) !void
/// pushFirstBatchInline(items: []const T, exec_mode: ExecMode) !void
///
/// pushLast(item: T, exec_mode: ExecMode) void / !void
/// pushLastInline(item: T, exec_mode: ExecMode) void / !void
/// pushLastBatch(items: []const T, exec_mode: ExecMode) !void
/// pushLastBatchInline(items: []const T, exec_mode: ExecMode) !void
///
/// popFirst(exec_mode: ExecMode) T / ?T
/// popFirstInline(exec_mode: ExecMode) T / ?T
/// popFirstBatch(buf: []T, exec_mode: ExecMode) !usize
/// popFirstBatchInline(buf: []T, exec_mode: ExecMode) !usize
///
/// popLast(exec_mode: ExecMode) T / ?T
/// popLastInline(exec_mode: ExecMode) T / ?T
/// popLastBatch(buf: []T, exec_mode: ExecMode) !usize
/// popLastBatchInline(buf: []T, exec_mode: ExecMode) !usize
///
/// peekFirst(exec_mode: ExecMode) ?T
/// peekFirstInline(exec_mode: ExecMode) ?T
/// peekFirstBatch?
///
/// peekLast(exec_mode: ExecMode) ?T
/// peekLastInline(exec_mode: ExecMode) ?T
/// peekLastBatch?
///
/// peekIndex(index: usize, exec_mode: ExecMode) T / !T
/// peekIndexInline(index: usize, exec_mode: ExecMode) T / !T
/// peekIndexBatch?
///
/// flushFirst(n: usize: buf: ?[]T, exec_mode) !usize
/// flushFirstInline(n: usize, buf: ?[]T, exec_mode) !usize
/// flushLast(n: usize, buf: ?[]T, exec_mode) !usize
/// flushLastInline(n: usize, buf: ?[]T, exec_mode) !usize
///
/// stockFirst(buf: []T) !void
/// stockLast(buf: []T) !void
///
/// reset() !void
/// resetDeep() void
///
/// straight() !void
///
/// grow() !void
/// shrink() !void
/// resize(new_capacity: usize, side: enum { before, after }) !void
///
/// ------------------------------------------------------------------------------------------------
pub fn CircularBuffer(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the buffer, asserted to be a power of 2 (efficiency reasons)
            init_capacity: usize = 32,
            // whether the buffer can auto grow beyond `init_capacity`
            growable: bool = true,
            // whether the buffer can auto shrink when grown past `init_capacity`,
            // size will half when used space falls below 1/4 of capacity
            shrinkable: bool = true,
        };

        //  fields (est: 88B size, 8B align)
        // ----------|------------------------------------------------------------------------------
        // allocator | used for creation and resizing of buffer when `memory_mode` is *alloc*
        // options   | configurable behavior for this structure
        // buffer    | space containing the stored items
        // head      | index of the item at lowest address in `buffer`
        // tail      | index of the item at highest address in `buffer`
        // total     | number of items currently stored
        // metadata  | holds state about this structure
        // -----------------------------------------------------------------------------------------
        allocator: ?Allocator,
        options: Options,
        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        total: usize = 0,
        metadata: u8,

        const meta_msk_is_init: u8 = 0b0000_0001;

        /// Initialize the buffer with the active `memory_mode` branch (read more *MemoryMode*).
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// alloc     | fn (allocator: Allocator, comptime options: Options) Allocator.Error!Self
        /// buffer    | fn (buf: []T, comptime options: Options) Self
        /// comptime  | fn (comptime options: Options) Self
        /// ----------------------------------------------------------------------------------------
        pub const init = switch (memory_mode) { // * comptime prune
            .alloc => initAlloc,
            .buffer => initBuffer,
            .@"comptime" => initComptime,
        };

        /// Initialize the buffer for using heap allocation.
        /// Issue key specs:
        /// - Panic when `options.init_capacity` is zero or not power of two.
        /// - Throws *OutOfMemory* when allocation process fail.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) Allocator.Error!Self {
            comptime assertAndMsg(options.init_capacity > 0, "Can't initiate with zero size.", .{});
            comptime assertPowerOf2(options.init_capacity);

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
                .metadata = meta_msk_is_init,
            };
        }

        /// Initialize the buffer for working with user provided `buf`.
        /// Issue key specs:
        /// - Panic when `buf.len` is zero or not power of two.
        inline fn initBuffer(buf: []T, comptime options: Options) Self {
            assertAndMsg(buf.len > 0, "Can't initiate with zero size.", .{});
            assertPowerOf2(buf.len);

            _ = options;

            return .{
                .buffer = buf,
                .options = .{
                    .init_capacity = 0, // * want this to be `buf.len` but no comptime guarantee (won't impact flow)
                    .growable = false,
                    .shrinkable = false,
                },
                .allocator = null,
                .metadata = meta_msk_is_init,
            };
        }

        /// Initialize the buffer for using comptime memory allocation.
        /// Issue key specs:
        /// - Panic when `options.init_capacity` is zero or not power of two.
        inline fn initComptime(comptime options: Options) Self {
            assertComptime(@src().fn_name);
            assertAndMsg(options.init_capacity > 0, "Can't initiate with zero size.", .{});
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
        /// - Panic when called (only *.buffer* and *.@"comptime"* `memory_mode`).
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .buffer, .@"comptime" => {
                    @compileError("The buffer isn't allocated on the heap (remove call 'deinit').");
                },
                .alloc => {
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

        /// Reset buffer's metadata to zero.
        /// * most often no reason for the user to call.
        pub inline fn metaReset(self: *Self) void {
            self.metadata = 0;
        }

        /// Check buffer's init status.
        /// * most often no reason for the user to call.
        pub inline fn metaInitStatus(self: *const Self) bool {
            return meta_msk_is_init == (self.metadata & meta_msk_is_init);
        }

        /// Returns the length of the underlying buffer (unit `T`).
        /// Time - *O(1)*, direct value access.
        pub inline fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Returns the number of items occupying the buffer.
        /// Time - *O(1)*, direct value access.
        pub inline fn size(self: *const Self) usize {
            return self.total;
        }

        /// Check if the buffer is empty.
        /// Time - *O(1)*, single comparison.
        pub inline fn isEmpty(self: *const Self) bool {
            return self.total == 0;
        }

        /// Check if the buffer is full.
        /// Time - *O(1)*, single comparison.
        pub inline fn isFull(self: *const Self) bool {
            return self.total == self.buffer.len;
        }

        /// Check if `ptr` holds the address of the current 'self.buffer'.
        /// Time - *O(1)*, single comparison.
        pub inline fn isValidRef(self: *const Self, ptr: *const []T) bool {
            return ptr == &self.buffer;
        }

        /// Check if the capacity increase of `amount` would overflow *usize*.
        /// Time - *O(1)*, basic operation.
        /// Issue key specs:
        /// - Return-code 0 (ok) or 1 (warn) if overflow.
        /// * most often no reason for the user to call.
        pub inline fn checkCapacityIncrease(self: *const Self, amount: usize) u8 {
            const result = @addWithOverflow(self.buffer.len, amount);
            return result[1];
        }

        /// Store an `item` first in the buffer.
        /// Time - *O(1)/O(n)*, may grow capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | user has manual control over 'grow' routine.
        /// Issue key specs:
        /// - Throws *NotEnoughSpace* when capacity has to grow as `self.options.growable` is *false*.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn pushFirst(self: *Self, item: T, comptime exec_mode: ExecMode) switch (exec_mode) {
            .uncheck => void,
            .safe => (Allocator.Error || BufferError)!void,
        } {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            // grow?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => if (self.total == self.buffer.len) {
                    switch (memory_mode) { // * comptime prune
                        .buffer => return error.NotEnoughSpace,
                        .alloc, .@"comptime" => switch (self.options.growable) { // * comptime prune
                            false => return error.NotEnoughSpace,
                            true => {
                                self.grow() catch |err| switch (err) {
                                    error.OutOfMemory => |e| return e,
                                    else => unreachable,
                                };
                            },
                        },
                    }
                },
            }

            // adjust 'head'?
            switch (self.total == 0) {
                true => {}, // * skip decrement, 'head' already points to valid slot
                false => self.head = wrapDecrement(usize, self.head, 0, self.buffer.len),
            }

            self.buffer[self.head] = item;
            self.total += 1;
        }

        /// Identical to 'pushFirst' but guaranteed to be inlined.
        pub inline fn pushFirstInline(self: *Self, item: T, comptime exec_mode: ExecMode) if (exec_mode == .uncheck) void else anyerror!void {
            return @call(.always_inline, pushFirst, .{ self, item, exec_mode });
        }

        /// Push all `items` first in the buffer.
        /// Time - *O(n)*, linear flow, may grow capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when required capacity overflows *usize*.
        /// Issue key specs:
        /// - Throws *Overflow* when required capacity overflows *usize*.
        /// - Throws *NotEnoughSpace* when capacity has to grow as `self.options.growable` is *false*.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn pushFirstBatch(self: *Self, items: []const T, comptime exec_mode: ExecMode) (Allocator.Error || BufferError || ValueError)!void {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            const required_capacity = switch (exec_mode) { // * comptime prune
                .uncheck => self.total + items.len,
                .safe => {
                    if (items.len == 0) return;
                    try checkedAdd(self.total, items.len);
                },
            };

            // grow?
            if (required_capacity > self.buffer.len) {
                switch (memory_mode) { // * comptime prune
                    .buffer => return error.NotEnoughSpace,
                    .alloc, .@"comptime" => switch (self.options.growable) { // * comptime prune
                        false => return error.NotEnoughSpace,
                        true => {
                            const new_capacity = try nextPowerOf2(required_capacity);
                            self.resize(new_capacity, .before) catch |err| switch (err) {
                                error.OutOfMemory => |e| return e,
                                else => unreachable,
                            };
                        },
                    },
                }
            }

            // linear flow, respects the expected order for pushed items -->

            const last_index = items.len - 1;

            for (0..last_index) |i| {
                self.buffer[self.head] = items[i];
                self.head = wrapDecrement(usize, self.head, 0, self.buffer.len);
            }

            self.buffer[self.head] = items[last_index];
            self.total = required_capacity;

            switch (self.total == 0) {
                true => {}, // * skip decrement, 'head' already points to valid slot
                false => self.head = wrapDecrement(usize, self.head, 0, self.buffer.len),
            }
        }

        /// Identical to 'pushFirstBatch' but guaranteed to be inlined.
        pub inline fn pushFirstBatchInline(self: *Self, items: []const T, comptime exec_mode: ExecMode) !void {
            return @call(.always_inline, pushFirstBatch, .{ self, items, exec_mode });
        }

        /// Store an `item` last in the buffer.
        /// Time - *O(1)/O(n)*, may grow capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | user has manual control over 'grow' routine.
        /// Issue key specs:
        /// - Throws *NotEnoughSpace* when capacity has to grow as `self.options.growable` is *false*.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn pushLast(self: *Self, item: T, comptime exec_mode: ExecMode) switch (exec_mode) {
            .uncheck => void,
            .safe => (Allocator.Error || BufferError)!void,
        } {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            // grow?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => if (self.total == self.buffer.len) {
                    switch (memory_mode) { // * comptime prune
                        .buffer => return error.NotEnoughSpace,
                        .alloc, .@"comptime" => switch (self.options.growable) { // * comptime prune
                            false => return error.NotEnoughSpace,
                            true => {
                                self.grow() catch |err| switch (err) {
                                    error.OutOfMemory => |e| return e,
                                    else => unreachable,
                                };
                            },
                        },
                    }
                },
            }

            // adjust 'tail'?
            switch (self.total == 0) {
                true => {}, // * skip increment, 'tail' already points to valid slot
                false => self.tail = wrapIncrement(usize, self.tail, 0, self.buffer.len),
            }

            self.buffer[self.tail] = item;
            self.total += 1;
        }

        /// Identical to 'pushLast' but guaranteed to be inlined.
        pub inline fn pushLastInline(self: *Self, item: T, comptime exec_mode: ExecMode) if (exec_mode == .uncheck) void else anyerror!void {
            return @call(.always_inline, pushLast, .{ self, item, exec_mode });
        }

        /// Push all `items` last in the buffer.
        /// Time - *O(n)*, memory region copy, may grow capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when required capacity overflows *usize*.
        /// Issue key specs:
        /// - Throws *Overflow* when required capacity overflows *usize*.
        /// - Throws *NotEnoughSpace* when capacity has to grow as `self.options.growable` is *false*.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn pushLastBatch(self: *Self, items: []const T, comptime exec_mode: ExecMode) (Allocator.Error || BufferError || ValueError)!void {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            const required_capacity = switch (exec_mode) { // * comptime prune
                .uncheck => self.total + items.len,
                .safe => {
                    if (items.len == 0) return;
                    try checkedAdd(self.total, items.len);
                },
            };

            // grow?
            if (required_capacity > self.buffer.len) {
                switch (memory_mode) { // * comptime prune
                    .buffer => return error.NotEnoughSpace,
                    .alloc, .@"comptime" => switch (self.options.growable) { // * comptime prune
                        false => return error.NotEnoughSpace,
                        true => {
                            const new_capacity = try nextPowerOf2(required_capacity);
                            try self.resize(new_capacity, .after);
                        },
                    },
                }
                // * resized buffer has contiguous layout and is left justified
                const end_index = self.tail + items.len;
                @memcpy(self.buffer[self.tail + 1 .. end_index + 1], items);
                self.tail = end_index;
                self.total = required_capacity;
                return;
            }

            // memory region copy, accounting for edge cases -->

            //     h t      h t      h t        t     h    h/t
            // _._.x.x    _.x.x._    x.x._._    x._._.x    _._._._
            // ^                ^        ^        ^        ^
            // ws               ws       ws       ws       ws

            const write_start = if (self.total > 0) {
                fastMod(self.tail + 1, self.buffer.len);
            } else {
                self.tail;
            };

            const right_slot_len = self.buffer.len - write_start;
            const first_part_len = @min(items.len, right_slot_len);
            const is_two_parts = (first_part_len < items.len);

            const end_index = write_start + first_part_len;
            @memcpy(self.buffer[write_start..end_index], items[0..first_part_len]);

            if (is_two_parts) {
                end_index = items.len - first_part_len;
                @memcpy(self.buffer[0..end_index], items[first_part_len..]);
            }

            // adjust 'tail'
            self.tail = fastMod(write_start +% (items.len - 1), self.buffer.len);
            self.total = required_capacity;
        }

        /// Identical to 'pushLastBatch' but guaranteed to be inlined.
        pub inline fn pushLastBatchInline(self: *Self, items: []const T, comptime exec_mode: ExecMode) !void {
            return @call(.always_inline, pushLastBatch, .{ self, items, exec_mode });
        }

        /// Get the first item in the buffer, free its memory.
        /// Time - *O(1)/O(n)*, may shrink capacity.
        /// ExecMode:
        /// - safe    | can throw error
        /// - uncheck | manual control over 'shrink' routine, undefined when buffer is empty.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn popFirst(self: *Self, comptime exec_mode: ExecMode) switch (exec_mode) {
            .uncheck => T,
            .safe => Allocator.Error!?T,
        } {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            // empty?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => if (self.total == 0) return null,
            }

            const item = self.buffer[self.head];

            // adjust 'head'?
            switch (self.total == 0) {
                true => {}, // * skip increment, 'head' already points to valid slot
                false => self.head = wrapIncrement(usize, self.head, 0, self.buffer.len),
            }

            self.total -= 1;

            // shrink?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => switch (memory_mode) { // * comptime prune
                    .buffer => {},
                    .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                        false => {},
                        true => {
                            const a = (self.total >= self.options.init_capacity);
                            const b = (self.total <= self.buffer.len / 4);
                            if (a and b) self.shrink() catch |err| switch (err) {
                                error.OutOfMemory => |e| return e,
                                else => unreachable,
                            };
                        },
                    },
                },
            }

            return item;
        }

        /// Identical to 'popFirst' but guaranteed to be inlined.
        pub inline fn popFirstInline(self: *Self, comptime exec_mode: ExecMode) if (exec_mode == .uncheck) T else anyerror!?T {
            return @call(.always_inline, popFirst, .{ self, exec_mode });
        }

        /// Pop items from start of buffer into `buf`.
        /// Returns the number of items popped from the buffer.
        /// Time - *O(n)*, memory region copy, may shrink capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when buffer is empty or `buf.len` is zero.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn popFirstBatch(self: *Self, buf: []T, comptime exec_mode: ExecMode) Allocator.Error!usize {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            // empty?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => if (buf.len == 0 or self.total == 0) return 0,
            }

            // memory region copy, accounting for edge cases -->

            //     h t      h t      h t        t     h    h/t
            // _._.x.x    _.x.x._    x.x._._    x._._.x    _._._._

            const pop_len = @min(self.total, buf.len);

            const right_slot_len = self.buffer.len - self.head;
            const first_part_len = @min(pop_len, right_slot_len);
            const is_two_parts = (first_part_len < pop_len);
            const is_full_pop = (pop_len == self.total);

            const end_index = self.head + first_part_len;
            @memcpy(self.buffer[self.head..end_index], buf[0..first_part_len]);

            if (is_two_parts) {
                end_index = pop_len - first_part_len;
                @memcpy(self.buffer[0..end_index], buf[first_part_len..pop_len]);
            }

            // adjust 'head'
            const new_head = self.head +% if (!is_full_pop) pop_len else pop_len - 1;
            self.head = fastMod(new_head, self.buffer.len);
            self.total -= pop_len;

            // shrink?
            switch (memory_mode) { // * comptime prune
                .buffer => {},
                .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                    false => {},
                    true => {
                        const a = (self.total >= self.options.init_capacity);
                        const b = (self.total <= self.buffer.len / 4);
                        if (a and b) self.shrink() catch |err| switch (err) {
                            error.OutOfMemory => |e| return e,
                            else => unreachable,
                        };
                    },
                },
            }

            return pop_len;
        }

        /// Get the last item in the buffer, free its memory.
        /// Time - *O(1)/O(n)*, may shrink capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | manual control over 'shrink' routine, undefined when buffer is empty.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn popLast(self: *Self, comptime exec_mode: ExecMode) switch (exec_mode) {
            .uncheck => T,
            .safe => Allocator.Error!?T,
        } {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            // empty?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => if (self.total == 0) return null,
            }

            const item = self.buffer[self.tail];

            // adjust 'tail'?
            switch (self.total == 1) {
                true => {}, // * skip decrement, 'tail' points to only valid slot
                false => self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len),
            }

            self.total -= 1;

            // shrink?
            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => switch (memory_mode) { // * comptime prune
                    .buffer => {},
                    .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                        false => {},
                        true => {
                            const a = (self.total >= self.options.init_capacity);
                            const b = (self.total <= self.buffer.len / 4);
                            if (a and b) self.shrink() catch |err| switch (err) {
                                error.OutOfMemory => |e| return e,
                                else => unreachable,
                            };
                        },
                    },
                },
            }

            return item;
        }

        /// Identical to 'popLast' but guaranteed to be inlined.
        pub inline fn popLastInline(self: *Self, comptime exec_mode: ExecMode) if (exec_mode == .uncheck) T else anyerror!?T {
            return @call(.always_inline, popLast, .{ self, exec_mode });
        }

        /// Pop items from end of buffer into `buf`.
        /// Returns the number of items popped from the buffer.
        /// Time - *O(n)*, linear exec flow, may grow capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when buffer is empty or `buf.len` is zero.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn popLastBatch(self: *Self, buf: []T, comptime exec_mode: ExecMode) Allocator.Error!usize {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => {
                    if (self.total == 0 or buf.len == 0) return 0;
                },
            }

            // linear flow, respects the expected order for popped items -->

            const pop_len = @min(self.total, buf.len);
            const last_index = pop_len - 1;

            for (0..last_index) |i| {
                buf[i] = self.buffer[self.tail];
                self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len);
            }

            buf[last_index] = self.buffer[self.tail];
            self.total -= pop_len;

            switch (self.total == 1) {
                true => {}, // * skip decrement, 'tail' points to only valid slot
                false => self.tail = wrapDecrement(usize, self.tail, 0, self.buffer.len),
            }

            // shrink?
            switch (memory_mode) { // * comptime prune
                .buffer => {},
                .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                    false => {},
                    true => {
                        const a = (self.total >= self.options.init_capacity);
                        const b = (self.total <= self.buffer.len / 4);
                        if (a and b) self.shrink() catch |err| switch (err) {
                            error.OutOfMemory => |e| return e,
                            else => unreachable,
                        };
                    },
                },
            }

            return pop_len;
        }

        /// Identical to 'popLastBatch' but guaranteed to be inlined.
        pub inline fn popLastBatchInline(self: *Self, buf: []T, comptime exec_mode: ExecMode) !usize {
            return @call(.always_inline, popLastBatch, .{ self, buf, exec_mode });
        }

        /// Get the first item in the buffer.
        /// Time - *O(1)*, direct indexing.
        /// ExecMode:
        /// *.safe*    | -
        /// *.uncheck* | undefined when buffer is empty.
        pub fn peekFirst(self: *const Self, comptime exec_mode: ExecMode) ?T {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                    if (self.total == 0) return null;
                },
            }

            return self.buffer[self.head];
        }

        /// Identical to 'peekFirst' but guaranteed to be inlined.
        pub inline fn peekFirstInline(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, peekFirst, .{ self, exec_mode });
        }

        /// Get the last item in the buffer.
        /// Time - *O(1)*, direct indexing.
        /// ExecMode:
        /// - safe    | -
        /// - uncheck | undefined when buffer is empty.
        pub fn peekLast(self: *const Self, comptime exec_mode: ExecMode) ?T {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                    if (self.total != 0) {} else return null;
                },
            }

            return self.buffer[self.tail];
        }

        /// Identical to 'peekLast' but guaranteed to be inlined.
        pub inline fn peekLastInline(self: *const Self, comptime exec_mode: ExecMode) ?T {
            return @call(.always_inline, peekLast, .{ self, exec_mode });
        }

        /// Get an item at `index` of the buffer.
        /// Time - *O(1)*, modulus to direct indexing.
        /// ExecMode:
        /// - safe    | can throw error
        /// - uncheck | undefined when `index` is out of bounds.
        /// Issue key specs:
        /// - Throws *OutOfBounds* when `index` is not within buffer's size.
        pub fn peekIndex(self: *const Self, index: usize, comptime exec_mode: ExecMode) switch (exec_mode) {
            .uncheck => T,
            .safe => IndexError!T,
        } {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                    if (index >= self.total) return error.OutOfBounds;
                },
                // TODO! better and more accurate check
            }

            const sum = self.head +% index;
            const actual_index = fastMod(sum, self.buffer.len);
            return self.buffer[actual_index];
        }

        /// Identical to 'peekIndex' but guaranteed to be inlined.
        pub inline fn peekIndexInline(self: *const Self, index: usize, comptime exec_mode: ExecMode) if (exec_mode == .uncheck) T else anyerror!T {
            return @call(.always_inline, peekIndex, .{ self, index, exec_mode });
        }

        /// Flush `n` (max) items from start of buffer, into `buf` if not *null*.
        /// Returns the number of items flushed from the buffer.
        /// Time - *O(n)*, memory region copy, may shrink capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when buffer is empty or `n` or `buf.len` is zero.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn flushFirst(self: *Self, n: usize, buf: ?[]T, comptime exec_mode: ExecMode) Allocator.Error!usize {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => {
                    const a = (n == 0);
                    const b = (self.total == 0);
                    const c = (buf != null and buf.?.len == 0);
                    if (a or b or c) return 0;
                },
            }

            // memory region copy, accounting for edge cases -->

            //     h t      h t      h t        t     h    h/t
            // _._.x.x    _.x.x._    x.x._._    x._._.x    _._._._

            const flush_len = @min(self.total, n);
            if (buf) |_buf| flush_len = @min(flush_len, _buf.len);

            const right_side_len = self.buffer.len - self.head;
            const first_part_len = @min(flush_len, right_side_len);
            const is_two_parts = (first_part_len < flush_len);
            const is_full_flush = (flush_len == self.total);

            // copy to `buf` if provided
            if (buf) |_buf| {
                const end_index = self.head + first_part_len;
                @memcpy(self.buffer[self.head..end_index], _buf[0..first_part_len]);

                if (is_two_parts) {
                    end_index = flush_len - first_part_len;
                    @memcpy(self.buffer[0..end_index], _buf[first_part_len..flush_len]);
                }
            }

            // adjust 'head'
            const new_head = self.head +% if (!is_full_flush) flush_len else flush_len - 1;
            self.head = fastMod(new_head, self.buffer.len);
            self.total -= flush_len;

            // shrink?
            switch (memory_mode) { // * comptime prune
                .buffer => {},
                .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                    false => {},
                    true => {
                        const a = (self.total >= self.options.init_capacity);
                        const b = (self.total <= self.buffer.len / 4);
                        if (a and b) self.shrink() catch |err| switch (err) {
                            error.OutOfMemory => |e| return e,
                            else => unreachable,
                        };
                    },
                },
            }

            return flush_len;
        }

        /// Identical to 'flushFirst' but guaranteed to be inlined.
        pub inline fn flushFirstInline(self: *Self, buf: ?[]T, comptime exec_mode: ExecMode) !usize {
            return @call(.always_inline, flushFirst, .{ self, buf, exec_mode });
        }

        /// Flush `n` (max) items taken last from buffer, into `buf` if not *null*.
        /// Returns the number of items flushed from the buffer.
        /// Time - *O(n)*, memory region copy, may shrink capacity.
        /// ExecMode:
        /// - safe    | can throw error.
        /// - uncheck | can throw error, undefined when buffer is empty or `n` or `buf.len` is zero.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn flushLast(self: *Self, n: usize, buf: ?[]T, comptime exec_mode: ExecMode) Allocator.Error!usize {
            switch (exec_mode) { // * comptime prune
                .uncheck => @setRuntimeSafety(false),
                .safe => {
                    self.assertInit();
                    if (memory_mode == .@"comptime") assertComptime(@src().fn_name);
                },
            }

            switch (exec_mode) { // * comptime prune
                .uncheck => {},
                .safe => {
                    const a = (n == 0);
                    const b = (self.total == 0);
                    const c = (buf != null and buf.?.len == 0);
                    if (a or b or c) return 0;
                },
            }

            // memory region copy, accounting for edge cases -->

            //     h t      h t      h t        t     h    h/t
            // _._.x.x    _.x.x._    x.x._._    x._._.x    _._._._

            const flush_len = @min(self.total, n);
            if (buf) |_buf| flush_len = @min(flush_len, _buf.len);

            const left_side_len = self.tail + 1;
            const first_part_len = @min(flush_len, left_side_len);
            const second_part_len = flush_len - first_part_len;
            const is_two_parts = (first_part_len < flush_len);
            const is_full_flush = (flush_len == self.total);

            // copy to `buf` if provided
            if (buf) |_buf| {
                const start_index = self.tail - (first_part_len - 1);
                @memcpy(self.buffer[start_index .. self.tail + 1], _buf[0..first_part_len]);

                if (is_two_parts) {
                    start_index = self.buffer.len - second_part_len;
                    @memcpy(self.buffer[start_index..self.buffer.len], _buf[first_part_len..flush_len]);
                }
            }

            // adjust 'tail' (modulus not practical)
            if (is_two_parts) {
                self.tail = self.buffer.len;
                self.tail -= if (!is_full_flush) second_part_len + 1 else second_part_len;
            } else {
                self.tail -= if (!is_full_flush) first_part_len else first_part_len - 1;
            }

            self.total -= flush_len;

            // shrink?
            switch (memory_mode) { // * comptime prune
                .buffer => {},
                .alloc, .@"comptime" => switch (self.options.shrinkable) { // * comptime prune
                    false => {},
                    true => {
                        const a = (self.total >= self.options.init_capacity);
                        const b = (self.total <= self.buffer.len / 4);
                        if (a and b) self.shrink() catch |err| switch (err) {
                            error.OutOfMemory => |e| return e,
                            else => unreachable,
                        };
                    },
                },
            }

            return flush_len;
        }

        /// Identical to 'flushLast' but guaranteed to be inlined.
        pub fn flushLastInline(self: *Self, n: usize, buf: ?[]T, comptime exec_mode: ExecMode) !usize {
            return @call(.always_inline, flushLast, .{ self, n, buf, exec_mode });
        }

        /// Set content of buffer with provided `buf`.
        /// Time - *O(n)*, memory region copy.
        /// Issue key specs:
        /// - Throws *NotEnoughSpace* when `buf` has length that exceeds the buffer size.
        pub fn stockFirst(self: *Self, buf: []T) BufferError!void {
            _ = self;
            _ = buf;
        }

        pub fn stockLast(self: *Self) void {
            _ = self;
        }

        //pub fn reset(self: *Self, mode: struct { simple, shallow, deep }) {
        //}

        /// Reset the buffer to its empty initial state.
        /// Time - *O(1)/O(n)*, resize if buffer is not initial-sized.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when allocation process fail (only *alloc* `memory_mode`).
        pub fn reset(self: *Self) switch (memory_mode) {
            .alloc => Allocator.Error!void,
            else => void,
        } {
            // re-alloc?
            switch (memory_mode) {
                .buffer => {},
                .alloc => {
                    if (self.buffer.len != self.options.init_capacity) {
                        // alloc buffer with 'self.init_capacity'
                        const ally = self.allocator orelse unreachable;
                        ally.free(self.buffer);
                        self.buffer = try ally.alloc(T, self.options.init_capacity);
                    }
                },
                .@"comptime" => { // * not free-after-use, compiler promotes
                    assertComptime(@src().fn_name);
                    if (self.buffer.len != self.options.init_capacity) {
                        // alloc buffer with 'self.init_capacity'
                        var buf: [self.options.init_capacity]T = undefined;
                        self.buffer = &buf;
                    }
                },
            }
            self.head = 0;
            self.tail = 0;
            self.total = 0;
        }

        /// Reset the buffer to its empty initial state.
        /// Time - *O(1)*, direct assignment.
        pub fn resetShallow(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.total = 0;
        }

        /// Reset the buffer to its empty initial state.
        /// Time - *O(n)*,
        pub fn resetDeep() void {}

        /// Ensure contiguous memory layout by straightening out the buffer.
        /// Time - *O(n)*, clone content.
        /// Issue key specs:
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn straight(self: *Self) !void {
            // TODO, how to handle buffer which can't allocate new.
            if (self.head == 0) return;
            try self.resize(self, self.buffer.len, .after);
        }

        /// Copy over current content into new buffer of **twice** the size.
        /// Time - *O(n)*, clone content.
        /// Issue key specs:
        /// - Throws *Overflow* when new capacity would overflow *usize*.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn grow(self: *Self) (Allocator.Error || BufferError || ValueError)!void {
            const new_capacity = try checkedMul(self.buffer.len, 2);
            try self.resize(new_capacity, .after);
        }

        /// Copy over current content into new buffer of **half** the size.
        /// Time - *O(n)*, clone content.
        /// Issue key specs:
        /// - Throws *NotEnoughSpace* when new capacity wouldn't fit all content in buffer.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn shrink(self: *Self) (Allocator.Error || BufferError)!void {
            const new_capacity = self.buffer.len / 2;
            try self.resize(new_capacity, .after);
        }

        /// Copy over current content into new buffer of size `new_capacity`.
        /// Asserts `new_capacity` to be a power of two.
        /// Time - *O(n)*, clone content.
        /// Issue key specs:
        /// - Throws *NotEnoughSpace* when `new_capacity` has less capacity than buffer's content.
        /// - Throws *OutOfMemory* when resize allocation fail (only *alloc* `memory_mode`).
        pub fn resize(self: *Self, new_capacity: usize, comptime side: enum { before, after }) !void {
            @setRuntimeSafety(false); // verified ok
            self.assertInit();

            if (new_capacity < self.total) return error.NotEnoughSpace;
            assertPowerOf2(new_capacity);

            const new_buffer = switch (memory_mode) { // * comptime branch prune
                .buffer => @compileError("Can't resize space of static buffer."),
                .alloc => b: {
                    const ally = self.allocator orelse unreachable;
                    const buf = try ally.alloc(T, new_capacity);
                    break :b buf;
                },
                .@"comptime" => b: { // * not free-after-use, compiler promotes
                    assertComptime(@src().fn_name);
                    var buf: [new_capacity]T = undefined;
                    break :b &buf;
                },
            };

            switch (side) { // * comptime branch prune
                .after => {
                    if (self.total == 0) {} else if (self.head < self.tail) {
                        // * memory is contiguous
                        const old_mem = self.buffer[self.head .. self.tail + 1];
                        const new_mem = new_buffer[0..self.total];
                        @memcpy(new_mem, old_mem);
                        self.head = 0;
                        self.tail = self.total - 1;
                    } else {
                        // * memory is wrapped
                        const second_part_len = self.tail + 1;
                        // copy over first part
                        const old_mem_a = self.buffer[self.head..];
                        const new_mem_a = new_buffer[0..old_mem_a.len];
                        @memcpy(new_mem_a, old_mem_a);
                        // copy over second part
                        const old_mem_b = self.buffer[0..second_part_len];
                        const new_mem_b = new_buffer[old_mem_a.len .. old_mem_a.len + second_part_len];
                        @memcpy(new_mem_b, old_mem_b);
                        self.head = 0;
                        self.tail = self.total - 1;
                    }
                },
                .before => {
                    if (self.total == 0) {} else if (self.head < self.tail) {
                        // * memory is contiguous
                        const new_head = new_buffer.len - self.total;
                        const old_mem = self.buffer[self.head .. self.tail + 1];
                        const new_mem = new_buffer[new_head..];
                        @memcpy(new_mem, old_mem);
                        self.head = new_head;
                        self.tail = new_buffer.len - 1;
                    } else {
                        // * memory is wrapped
                        const new_head = new_buffer.len - self.total;
                        // copy over first part
                        const old_mem_a = self.buffer[self.head..];
                        const new_mem_a = new_buffer[new_head..];
                        @memcpy(new_mem_a, old_mem_a);
                        // copy over second part
                        const old_mem_b = self.buffer[0 .. self.tail + 1];
                        const new_mem_b = new_buffer[new_head + new_mem_a.len ..];
                        @memcpy(new_mem_b, old_mem_b);
                        self.head = new_head;
                        self.tail = new_buffer.len - 1;
                    }
                },
            }

            if (memory_mode == .alloc) {
                const ally = self.allocator orelse unreachable;
                ally.free(self.buffer);
            }

            self.buffer = new_buffer;
        }
    };
}

// testing -->

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "CircularBuffer" {
    const allocator = std.testing.allocator;
    const T_cbuf = CircularBuffer(u8, .alloc);
    var cbuf: T_cbuf = try T_cbuf.init(allocator, .{
        .init_capacity = 2,
        .growable = false,
        .shrinkable = false,
    });

    // empty state
    try expectEqual(true, cbuf.metaInitStatus());
    try expectEqual(2, cbuf.capacity());
    try expectEqual(0, cbuf.size());
    try expectEqual(true, cbuf.isEmpty());
    try expectEqual(false, cbuf.isFull());
    try expectEqual(true, cbuf.isValidRef(&(cbuf.buffer)));
    try expectError(error.Underflow, cbuf.popFirst(.safe));
    try expectError(error.Underflow, cbuf.popLast(.safe));
    try expectEqual(null, cbuf.peekFirst(.safe));
    try expectEqual(null, cbuf.peekLast(.safe));
    try expectError(error.OutOfBounds, cbuf.peekIndex(0, .safe));

    // push
    try cbuf.pushFirst(1, .safe);
    try cbuf.pushLast(2, .safe);
    try expectEqual(2, cbuf.size());
    try expectEqual(&[_]u8{ 1, 2 }, cbuf.buffer);
    try expectEqual([_]usize{ 0, 1 }, [_]usize{ cbuf.head, cbuf.tail });
    try expectError(error.NotEnoughSpace, cbuf.pushLast(3, .safe));
    try expectError(error.NotEnoughSpace, cbuf.pushFirst(3, .safe));
    try cbuf.reset();

    // push wrap
    try cbuf.pushFirst(1, .safe);
    try cbuf.pushFirst(2, .safe);
    try expectEqual(&[_]u8{ 1, 2 }, cbuf.buffer);
    try expectEqual([_]usize{ 1, 0 }, [_]usize{ cbuf.head, cbuf.tail });
    try cbuf.reset();
    try cbuf.pushLast(1, .safe);
    try cbuf.pushLast(1, .safe);
    cbuf.head = 1;
    cbuf.tail = 1;
    try cbuf.pushLast(1, .safe);
    try cbuf.pushLast(2, .safe);
    try expectEqual(&[_]u8{ 2, 1 }, cbuf.buffer);
    try expectEqual([_]usize{ 0, 0 }, [_]usize{ cbuf.head, cbuf.tail });
    try cbuf.reset();

    // push inline
    try cbuf.pushFirstInline(1, .safe);
    try cbuf.pushLastInline(2, .safe);
    try cbuf.reset();

    // push batch
    cbuf.head = 1;
    cbuf.tail = 1;
    try cbuf.pushFirstBatch(&[_]u8{ 1, 2 }, .safe);
    try expectEqual(&[_]u8{ 2, 1 }, cbuf.buffer);
    try expectEqual([_]usize{ 0, 1 }, [_]usize{ cbuf.head, cbuf.tail });
    try cbuf.reset();
    try cbuf.pushLastBatch(&[_]u8{ 1, 2 }, .safe);
    try expectEqual(&[_]u8{ 1, 2 }, cbuf.buffer);
    try expectEqual([_]usize{ 0, 1 }, [_]usize{ cbuf.head, cbuf.tail });

    // push batch wrap
    try cbuf.pushFirstBatch(&[_]u8{ 1, 2 }, .safe);
    try expectEqual(&[_]u8{ 1, 2 }, cbuf.buffer);
    try expectEqual([_]usize{ 1, 0 }, [_]usize{ cbuf.head, cbuf.tail });
    try expectError(error.NotEnoughSpace, cbuf.pushFirstBatch(&[_]u8{3}, .safe));
    try cbuf.reset();
    cbuf.head = 1;
    cbuf.tail = 1;
    try cbuf.pushLastBatch(&[_]u8{ 1, 2 }, .safe);
    try expectEqual(&[_]u8{ 2, 1 }, cbuf.buffer);
    try expectEqual([_]usize{ 1, 0 }, [_]usize{ cbuf.head, cbuf.tail });
    try expectError(error.NotEnoughSpace, cbuf.pushLastBatch(&[_]u8{3}, .safe));
    try cbuf.reset();

    // push batch inline
    try cbuf.pushFirstBatchInline(&[_]u8{ 1, 2 }, .safe);
    try cbuf.pushLastBatchInline(&[_]u8{ 1, 2 }, .safe);
    try cbuf.reset();
}

//
//test "Comptime DoubleEndedQueue" {
//    comptime {
//        const T_deque = DoubleEndedQueue(u8, .Comptime);
//        var deque: T_deque = T_deque.init(.{
//            .init_capacity = 4,
//            .growable = true,
//            .shrinkable = true,
//        });
//
//        // test empty state -->
//
//        try expectEqual(true, deque.metaInitStatus());
//        try expectEqual(4, deque.capacity());
//        try expectEqual(0, deque.length());
//        try expectEqual(true, deque.isEmpty());
//        try expectError(BufferError.Underflow, deque.popFirst(.safe));
//        try expectError(BufferError.Underflow, deque.popLast(.safe));
//        try expectEqual(null, deque.peekFirst(.safe));
//        try expectEqual(null, deque.peekLast(.safe));
//        try expectEqual(null, deque.peekIndex(0, .safe));
//
//        // test push and pop -->
//
//        try deque.pushFirst(1, .safe);
//        try deque.pushLast(2, .safe);
//        try expectEqual(2, deque.length());
//        try expectEqual(1, deque.popFirst(.safe));
//        try expectEqual(2, deque.popLast(.safe));
//
//        // x x x x
//        //   ^.---.
//        //   tail head
//
//        try expectEqual(true, deque.head == deque.tail);
//        try expectEqual(true, deque.isEmpty());
//
//        try deque.reset();
//
//        // test wrapping behavior -->
//
//        try deque.stock(&.{ 1, 2, 3, 4 });
//        _ = try deque.popFirst(.safe);
//        try deque.pushLast(5, .safe);
//
//        // 5 2 3 4
//        // ^ ^--.
//        // tail head
//
//        try expectEqual(0, deque.tail); // tail wrap
//
//        _ = try deque.popLast(.safe);
//        _ = try deque.popLast(.safe);
//        try deque.pushFirst(4, .safe);
//        try deque.pushFirst(5, .safe);
//
//        // 4 2 3 5
//        //     ^ ^--.
//        //     tail head
//
//        try expectEqual(3, deque.head); // head wrap
//
//        // test shrink ('popFirst') -->
//
//        deque.options.init_capacity = 8;
//        try deque.reset();
//        deque.options.init_capacity = 2; // * trick to trigger shrink earlier
//
//        try deque.pushFirst(1, .safe);
//        try deque.pushLast(2, .safe);
//        try deque.pushFirst(3, .safe);
//
//        // 2 x x x x x 3 1
//        // ^           ^
//        // tail        head
//
//        try expectEqual(8, deque.capacity());
//        _ = try deque.popFirst(.safe); // shrink trigger
//        try expectEqual(4, deque.capacity());
//
//        // 1 2 x x
//        // ^ ^--.
//        // head tail
//
//        try expectEqual(1, deque.peekIndex(0, .safe));
//        try expectEqual(2, deque.peekIndex(1, .safe));
//        try expectEqual(null, deque.peekIndex(2, .safe));
//
//        // test grow ('pushFirst') -->
//
//        try deque.pushFirst(3, .safe);
//        try deque.pushFirst(4, .safe);
//        try expectEqual(true, deque.isFull());
//
//        // 1 2 4 3
//        //   ^ ^--.
//        //   tail head
//
//        try expectEqual(4, deque.capacity());
//        try deque.pushFirst(5, .safe); // growth trigger
//        try expectEqual(8, deque.capacity());
//
//        // 4 3 1 2 x x 5
//        //         ^   ^.
//        //         tail head
//
//        try expectEqual(5, deque.peekIndex(0));
//        try expectEqual(4, deque.peekIndex(1));
//        try expectEqual(3, deque.peekIndex(2));
//        try expectEqual(1, deque.peekIndex(3));
//        try expectEqual(2, deque.peekIndex(4));
//
//        // test shrink ('popLast') -->
//
//        _ = try deque.popFirst(.safe);
//        _ = try deque.popFirst(.safe);
//
//        // x x 3 1 2 x x x
//        //     ^   ^.
//        //     head tail
//
//        deque.options.init_capacity = 2;
//
//        try expectEqual(8, deque.capacity());
//        _ = try deque.popLast(.safe); // shrink trigger
//        try expectEqual(4, deque.capacity());
//
//        // 3 1 x x
//        // ^ ^--.
//        // head tail
//
//        try expectEqual(3, deque.buffer[0]);
//        try expectEqual(1, deque.buffer[1]);
//
//        deque.options.init_capacity = 4;
//
//        // test grow ('pushLast') -->
//
//        try deque.pushFirst(4, .safe);
//        try deque.pushFirst(5, .safe);
//        try expectEqual(true, deque.isFull());
//
//        // 3 1 5 4
//        //   ^ ^--.
//        //   tail head
//
//        try expectEqual(4, deque.capacity());
//        try deque.pushLast(6, .safe); // growth trigger
//        try expectEqual(8, deque.capacity());
//
//        // 5 4 3 1 6 x x x
//        // ^       ^
//        // head    tail
//
//        try expectEqual(5, deque.buffer[0]);
//        try expectEqual(4, deque.buffer[1]);
//        try expectEqual(3, deque.buffer[2]);
//        try expectEqual(1, deque.buffer[3]);
//        try expectEqual(6, deque.buffer[4]);
//
//        // test overflow error -->
//
//        deque.options.growable = false;
//
//        try deque.pushLast(7, .safe);
//        try deque.pushLast(8, .safe);
//        try deque.pushLast(9, .safe);
//
//        try expectError(BufferError.Overflow, deque.pushLast(10, .safe));
//
//        // test batch push -->
//
//        deque.options.growable = true;
//        deque.options.init_capacity = 5;
//        deque.reset();
//
//        deque.head = 2;
//        deque.pushFirst(1, .safe);
//        deque.pushFirst(2, .safe);
//        deque.pushFirst(3, .safe);
//
//        try deque.pushFirstBatch(&.{ 4, 5 });
//
//        try expectEqual(4, deque.buffer[0]);
//        try expectEqual(5, deque.buffer[1]);
//        try expectEqual(1, deque.buffer[2]);
//        try expectEqual(2, deque.buffer[3]);
//        try expectEqual(3, deque.buffer[4]);
//    }
//}
//
//test "Allocated DoubleEndedQueue" {
//    const allocator = std.testing.allocator;
//    const T_deque = DoubleEndedQueue(u8, .alloc);
//    var deque: T_deque = try T_deque.init(allocator, .{
//        .init_capacity = 2,
//        .growable = false,
//        .shrinkable = false,
//    });
//
//    defer deque.deinit();
//
//    // test general use -->
//
//    try expectEqual(2, deque.capacity());
//    try expectEqual(0, deque.length());
//    try expectEqual(true, deque.isEmpty());
//    try expectError(BufferError.Underflow, deque.popFirst(.safe));
//    try expectError(BufferError.Underflow, deque.popLast(.safe));
//    try expectEqual(null, deque.peekFirst(.safe));
//    try expectEqual(null, deque.peekLast(.safe));
//    try expectEqual(null, deque.peekIndex(0, .safe));
//
//    try deque.pushFirst(1, .safe);
//    try deque.pushLast(2, .safe);
//
//    try expectEqual(2, deque.length());
//    try expectEqual(true, deque.isFull());
//    try expectError(BufferError.Overflow, deque.pushFirst(3, .safe));
//    try expectError(BufferError.Overflow, deque.pushLast(4, .safe));
//
//    try expectEqual(1, deque.peekFirst(.safe));
//    try expectEqual(2, deque.peekLast(.safe));
//    try expectEqual(1, deque.peekIndex(0, .safe));
//    try expectEqual(2, deque.peekIndex(1, .safe));
//
//    try expectEqual(1, deque.popFirst(.safe));
//    try expectEqual(2, deque.popLast(.safe));
//
//    try expectEqual(true, deque.isEmpty());
//}
//
//test "Buffered DoubleEndedQueue" {
//    var buffer: [2]u8 = undefined;
//    const T_deque = CircularBuffer(u8, .buffer);
//    var deque: T_deque = T_deque.init(&buffer, .{});
//
//    // test general use -->
//
//    try expectEqual(2, deque.capacity());
//    try expectEqual(0, deque.length());
//    try expectEqual(true, deque.isEmpty());
//    try expectError(BufferError.Underflow, deque.popFirst(.safe));
//    try expectError(BufferError.Underflow, deque.popLast(.safe));
//    try expectEqual(null, deque.peekFirst(.safe));
//    try expectEqual(null, deque.peekLast(.safe));
//    try expectEqual(null, deque.peekIndex(0, .safe));
//
//    try deque.pushFirst(1, .safe);
//    try deque.pushLast(2, .safe);
//
//    try expectEqual(2, deque.length());
//    try expectEqual(true, deque.isFull());
//    try expectError(BufferError.Overflow, deque.pushFirst(3, .safe));
//    try expectError(BufferError.Overflow, deque.pushLast(4, .safe));
//
//    try expectEqual(1, deque.peekFirst(.safe));
//    try expectEqual(2, deque.peekLast(.safe));
//    try expectEqual(1, deque.peekIndex(0, .safe));
//    try expectEqual(2, deque.peekIndex(1, .safe));
//
//    try expectEqual(1, deque.popFirst(.safe));
//    try expectEqual(2, deque.popLast(.safe));
//
//    try expectEqual(true, deque.isEmpty());
//}
