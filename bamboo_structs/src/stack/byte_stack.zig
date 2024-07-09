const std = @import("std");
const builtin = @import("builtin");

const root = @import("./stack.zig");

const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;
const Error = root.Error;
const native_endian = builtin.cpu.arch.endian();
const panic = std.debug.panic;

// TODO: Implement 'growable' option like in './struct/queue/fifo.zig'

/// Can store any value and retrieve any value by translating between bytes.
/// Values are aligned to byte boundaries and stored within the fewest bytes.
pub const ByteStack = struct {
    const Self = @This();

    pub const Options = struct {
        comptime endian: Endian = native_endian,
        // growable: bool = false,
    };

    stack: []u8,
    top: usize,
    options: Options,
    allocator: ?Allocator,

    /// Initialize the stack with some `bytes`, configure with `options`.
    /// After use; release memory by calling 'deinit'.
    pub fn init(bytes: usize, options: Options, allocator: Allocator) !Self {
        return @call(.always_inline, initRuntime, .{ bytes, options, allocator });
    }

    /// Initialize the stack, allocating memory on the heap.
    /// After use; release memory by calling 'deinit'.
    pub fn initRuntime(bytes: usize, options: Options, allocator: Allocator) !Self {
        if (bytes == 0) panic("Can't initialize with zero size.", .{});
        return .{
            .stack = try allocator.alloc(u8, bytes),
            .top = bytes, // start at the top (stack grows downwards)
            .options = options,
            .allocator = allocator,
        };
    }

    /// Initialize the stack for comptime usage.
    /// Allocating memory in read-only data.
    pub fn initComptime(comptime bytes: usize, comptime options: Options) Self {
        if (!@inComptime()) panic("Invalid at runtime.", .{});
        if (bytes == 0) panic("Can't initialize with zero size.", .{});
        return .{
            .stack = blk: {
                var buf: [bytes]u8 = undefined;
                break :blk &buf; // pointer to ro-data
            },
            .top = bytes, // start at the top (stack grows downwards)
            .options = options,
            .allocator = null,
        };
    }

    /// Release allocated memory, cleanup routine for 'init'.
    pub fn deinit(self: *Self) void {
        if (self.allocator) |ally| {
            ally.free(self.stack);
        } else {
            panic("Can't deallocate with `null` allocator.", .{});
        }
    }

    /// Place copy of some `value` on top of the stack.
    pub inline fn push(self: *Self, value: anytype) !void {
        const size = @sizeOf(@TypeOf(value));

        if (size == 0) return;
        if (self.top < size) return Error.Overflow;

        const new_top = self.top - size;
        const dest = self.stack[new_top..self.top];
        self.top = new_top;

        if (self.options.endian == native_endian) {
            @memcpy(dest, std.mem.asBytes(&value));
        } else {
            const bytes = std.mem.asBytes(&value);
            std.mem.reverse(u8, &bytes);
            @memcpy(dest, bytes);
        }
    }

    /// Get a copy of some memory and free it from top of the stack.
    pub inline fn pop(self: *Self, comptime O: type) !O {
        return topCopy(self, O, true) orelse Error.Underflow;
    }

    /// Get a copy of some memory from top of the stack.
    pub inline fn peek(self: *Self, comptime O: type) ?O {
        return topCopy(self, O, false);
    }

    /// Return a copy of some memory from top of the stack.
    /// Specify `should_free` to also free the copied memory.
    inline fn topCopy(self: *Self, comptime O: type, should_free: bool) ?O {
        const size = @sizeOf(O);

        if (size == 0) return null;
        if (size > self.stack.len - self.top) return null;

        const new_top = self.top + size;
        const bytes = self.stack[self.top..new_top];
        if (should_free) self.top = new_top;

        if (self.options.endian == native_endian) {
            return @as(*align(1) const O, @ptrCast(bytes)).*;
        } else {
            var clone: [size]u8 = undefined;
            @memcpy(&clone, bytes);
            std.mem.reverse(u8, &clone);
            return @as(*align(1) const O, @ptrCast(&clone)).*;
        }
    }

    /// Check if the stack is empty.
    pub inline fn isEmpty(self: *Self) bool {
        return self.top == self.stack.len;
    }
};

// testing -->

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

test "peek empty stack expect null" {
    comptime {
        const bytes = 4;

        var vstack = ByteStack.initComptime(bytes, .{});
        const result = vstack.peek(u8);

        expectEqual(null, result) catch unreachable;
    }
}

test "pop empty stack expect underflow error" {
    comptime {
        const bytes = 4;

        var vstack = ByteStack.initComptime(bytes, .{});
        const result = vstack.pop(u8);

        expectError(Error.Underflow, result) catch unreachable;
    }
}

test "push too big expect overflow error" {
    comptime {
        const bytes = 3;

        var vstack = ByteStack.initComptime(bytes, .{});
        const result = vstack.push(@as(u32, 4444));

        expectError(Error.Overflow, result) catch unreachable;
    }
}

test "push one and pop one" {
    comptime {
        const bytes = 4;
        const value: u8 = 4;

        var vstack = ByteStack.initComptime(bytes, .{});
        vstack.push(value) catch unreachable;
        const _value = vstack.pop(u8);

        expectEqual(value, _value) catch unreachable;
    }
}

test "push one and pop one (runtime)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const bytes = 4;
    const value: u8 = 4;

    var vstack = try ByteStack.initRuntime(bytes, .{}, arena.allocator());
    try vstack.push(value);
    const _value = vstack.pop(u8);

    try expectEqual(value, _value);
}

test "push two and pop two" {
    comptime {
        const bytes = 4;
        const value: u8 = 4;

        var vstack = ByteStack.initComptime(bytes, .{});
        vstack.push(value) catch unreachable;
        vstack.push(value) catch unreachable;
        const a = vstack.pop(u8);
        const b = vstack.pop(u8);

        expectEqual(value, a) catch unreachable;
        expectEqual(value, b) catch unreachable;
    }
}

test "push two small and pop one big" {
    comptime {
        const bytes = 4;
        const value: u8 = 0x4;

        var vstack = ByteStack.initComptime(bytes, .{});
        vstack.push(value) catch unreachable;
        vstack.push(value) catch unreachable;
        const result = vstack.pop(u16);

        expectEqual(0x0404, result) catch unreachable;
    }
}

test "push one big and pop one small" {
    comptime {
        const bytes = 4;
        const value: u16 = 0x0406;

        var vstack = ByteStack.initComptime(bytes, .{});
        vstack.push(value) catch unreachable;
        const result = vstack.pop(u8);

        expectEqual(0x06, result) catch unreachable;
    }
}

test "push one and pop one non-byte aligned" {
    comptime {
        const bytes = 4;
        const value: u8 = 7;
        var vstack = ByteStack.initComptime(bytes, .{});
        vstack.push(value) catch unreachable;
        const result = vstack.pop(u3);

        expectEqual(value, result) catch unreachable;
    }
}

test "check stack 'is_empty' attribute" {
    comptime {
        const bytes = 4;
        const value: u8 = 4;

        var vstack = ByteStack.initComptime(bytes, .{});

        expectEqual(vstack.isEmpty(), true) catch unreachable;

        vstack.push(value) catch unreachable;
        expectEqual(vstack.isEmpty(), false) catch unreachable;

        _ = vstack.pop(u8) catch unreachable;
        expectEqual(vstack.isEmpty(), true) catch unreachable;
    }
}
