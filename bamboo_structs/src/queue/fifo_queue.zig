const std = @import("std");

const root = @import("./queue.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const panic = std.debug.panic;

/// Queue items of type `T`, ordered First-In-First-Out.
/// Uses 'Ring Buffer' logic under the hood for O(1) push and pop operations.
pub fn FifoQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            init_capacity: u32 = 100,
            growable: bool = false,
        };

        buffer: []T,
        head: usize = 0,
        tail: usize = 0,
        len: usize = 0,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the queue with some `capacity`, configure with `options`.
        /// After use; release memory by calling 'deinit'.
        pub fn init(options: Options, allocator: Allocator) !Self {
            return @call(.always_inline, initRuntime, .{ options, allocator });
        }

        /// Initialize the queue, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        pub fn initRuntime(options: Options, allocator: Allocator) !Self {
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});

            return .{
                .buffer = try allocator.alloc(T, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue for comptime usage.
        /// Allocating memory in read-only data.
        pub fn initComptime(comptime options: Options) Self {
            if (!@inComptime()) panic("Invalid at runtime.", .{});
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});

            return .{
                .buffer = blk: {
                    var buf: [options.init_capacity]T = undefined;
                    break :blk &buf; // pointer to ro-data
                },
                .options = options,
                .allocator = null,
            };
        }

        /// Release allocated memory, cleanup routine for 'init'.
        pub fn deinit(self: *Self) void {
            if (self.allocator) |ally| {
                ally.free(self.stack);
            } else {
                panic("Can't use `null` allocator.", .{});
            }
        }

        /// Place copy of `item` at the first position in the queue.
        pub fn push(self: *Self, item: T) !void {
            if (self.len >= self.buffer.len) {
                if (self.options.growable) try self.grow() else return Error.Overflow;
            }

            // skip increment if queue is empty, `tail` already points to valid slot
            if (self.len != 0) self.tail = (self.tail + 1) % self.buffer.len;

            self.buffer[self.tail] = item;
            self.len += 1;
        }

        /// Get a copy of the first item from queue and free its memory.
        pub fn pop(self: *Self) !T {
            return topCopy(self, true) orelse Error.Underflow;
        }

        /// Get a copy of the first item from queue.
        pub fn peek(self: *Self) ?T {
            return topCopy(self, false);
        }

        /// Return a copy of the first item from the queue.
        /// Specify `should_free` to also free the copied memory.
        inline fn topCopy(self: *Self, should_free: bool) ?T {
            if (self.len == 0) return null;

            const item = self.buffer[self.head];

            if (should_free) {
                self.head = (self.head + 1) % self.buffer.len;
                self.len -= 1;
            }

            return item;
        }

        /// Copy over current content into new buffer of twice the size.
        fn grow(self: *Self) !void {
            const new_capacity = self.buffer.len * 2;
            const new_buffer = blk: {
                if (@inComptime()) {
                    var buf: [new_capacity]T = undefined;
                    break :blk &buf; // pointer to ro-data
                } else {
                    const buf = try self.allocator.?.alloc(T, new_capacity);
                    break :blk buf;
                }
            };

            if (self.head < self.tail) {
                // * `tail` is not wrapped around

                const whole_part_len = (self.tail - self.head) + 1;

                // copy over whole part
                const old_mem = self.buffer[self.head .. self.tail + 1];
                const new_mem = new_buffer[0..whole_part_len];
                @memcpy(new_mem, old_mem);
            } else {
                // * `tail` is wrapped around

                const first_part_len = self.len - self.head;

                // copy over first part
                const old_mem_a = self.buffer[self.head..self.len];
                const new_mem_a = new_buffer[0..first_part_len];
                @memcpy(new_mem_a, old_mem_a);

                // copy over second part
                const old_mem_b = self.buffer[0 .. self.tail + 1];
                const new_mem_b = self.buffer[first_part_len .. first_part_len + 1 + self.tail];
                @memcpy(new_mem_b, old_mem_b);
            }

            if (!@inComptime()) self.allocator.?.free(self.buffer);
            self.buffer = new_buffer;
            self.head = 0;
            self.tail = self.len;
        }
    };
}

// testing -->

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "peek empty queue expect null" {
    comptime {
        var queue = FifoQueue(u8).initComptime(.{});
        const result = queue.peek();

        expectEqual(null, result) catch unreachable;
    }
}

test "pop empty stack expect underflow error" {
    comptime {
        var queue = FifoQueue(u8).initComptime(.{});
        const result = queue.pop();

        expectError(Error.Underflow, result) catch unreachable;
    }
}

test "push one and pop one" {
    comptime {
        var queue = FifoQueue(u8).initComptime(.{});
        const value: u8 = 4;
        queue.push(value) catch unreachable;
        const _value = queue.pop();

        expectEqual(value, _value) catch unreachable;
    }
}

test "push one and pop one (runtime)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var queue = try FifoQueue(u8).initRuntime(.{}, arena.allocator());
    const value: u8 = 4;
    try queue.push(value);
    const _value = queue.pop();

    try expectEqual(value, _value);
}

test "push too many expect overflow error" {
    comptime {
        const capacity: u32 = 1;
        var queue = FifoQueue(u8).initComptime(.{ .init_capacity = capacity });
        _ = queue.push(4) catch unreachable;
        const result = queue.push(4);

        expectError(Error.Overflow, result) catch unreachable;
    }
}
