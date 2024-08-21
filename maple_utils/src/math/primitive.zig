//! Author: palsmo
//! Status: Done
//! About: Primitive Mathematical Operations

const std = @import("std");

const mod_assert = @import("../assert/root.zig");
const root_shared = @import("./shared.zig");
const root_float = @import("./float.zig");

const ValueError = root_shared.ValueError;
const assertType = mod_assert.misc.assertType;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const isFinite = root_float.isFinite;
const isInf = root_float.isInf;
const isNan = root_float.isNan;

/// Returns the sum of `a` + `b`.
/// Asserts `T` to be a numeric type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn checkedAdd(comptime T: type, a: T, b: T) !T {
    @setRuntimeSafety(false); // * (asm) removes testing of-flag twice (ReleaseSafe)
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat });
    switch (@typeInfo(T)) { // * comptime branch prune
        .ComptimeInt, .ComptimeFloat => return a + b,
        .Int => {
            const result = @addWithOverflow(a, b);
            return if (result[1] == 0) result[0] else ValueError.Overflow;
        },
        .Float => {
            const result = a + b;
            return if (isFinite(result)) result else ValueError.Overflow;
        },
    }
}

test checkedAdd {
    try expectEqual(7, checkedAdd(u8, 3, 4));
    try expectEqual(ValueError.Overflow, checkedAdd(u8, 128, 128));
    try expectEqual(7.0, checkedAdd(f16, 3, 4));
    try expectEqual(ValueError.Overflow, checkedAdd(f16, 32753, 32753));
}

/// Returns the sum of `int_a` + `int_b`.
/// Asserts `T` to be an integer type.
/// Compute - very cheap, basic operation and comparison.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeAdd(comptime T: type, int_a: T, int_b: T) !T {
    @setRuntimeSafety(false); // * removes testing of-flag twice in (ReleaseSafe, asm)
    comptime assertType(T, .{ .Int, .ComptimeInt });
    switch (T) { // * comptime branch prune
        comptime_int => return int_a + int_b,
        else => {
            const result = @addWithOverflow(int_a, int_b);
            switch (result[1]) {
                0 => return result[0],
                1 => return ValueError.Overflow,
            }
        },
    }
}

test safeAdd {
    try expectEqual(7, safeAdd(u8, 3, 4));
    try expectError(ValueError.Overflow, safeAdd(u8, 128, 128));
}

/// Returns the product of `int_a` * `int_b`.
/// Asserts `T` to be an integer type.
/// Compute - very cheap, basic operation and comparison.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeMul(comptime T: type, int_a: T, int_b: T) !T {
    @setRuntimeSafety(false); // * removes testing of-flag twice in asm (ReleaseSafe)
    comptime assertType(T, .{ .Int, .ComptimeInt });
    switch (T) { // * comptime branch prune
        comptime_int => return int_a * int_b,
        else => {
            const result = @mulWithOverflow(int_a, int_b);
            switch (result[1]) {
                0 => return result[0],
                1 => return ValueError.Overflow,
            }
        },
    }
}

test safeMul {
    // normal
    try expectEqual(6, safeMul(u8, 2, 3));
    try expectEqual(6, safeMul(i8, 2, 3));
    try expectEqual(6, safeMul(comptime_int, 2, 3));
    // issue
    try expectError(ValueError.Overflow, safeMul(u8, 16, 16));
    try expectEqual(ValueError.Overflow, safeMul(i8, 16, 8));
}

/// Returns the difference of `a` - `b`.
/// Asserts `T` to be an integer type.
/// Compute - very cheap, basic operation and comparison.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeSub(comptime T: type, int_a: T, int_b: T) !T {
    @setRuntimeSafety(false); // * removes testing of-flag twice in asm (ReleaseSafe)
    comptime assertType(T, .{ .Int, .ComptimeInt });
    switch (T) { // * comptime branch prune
        comptime_int => return int_a - int_b,
        else => {
            const result = @subWithOverflow(int_a, int_b);
            switch (result[1]) {
                0 => return result[0],
                1 => return ValueError.Underflow,
            }
        },
    }
}

test safeSub {
    // normal
    try expectEqual(4, safeSub(u8, 8, 4));
    try expectEqual(4, safeSub(i8, 8, 4));
    try expectEqual(4, safeSub(comptime_int, 8, 4));
    try expectEqual(-4, safeSub(comptime_int, 4, 8));
    // issue
    try expectError(ValueError.Underflow, safeSub(u8, 4, 8));
    try expectError(ValueError.Underflow, safeSub(i8, -128, 1));
}

/// Fast `int_a` modulus `int_b`, but `int_b` has to be a power of two.
/// Asserts `T` to be an *integer*.
/// Compute - very cheap, two basic operations.
pub inline fn fastMod(comptime T: type, int_a: T, int_b: T) T {
    comptime assertType(T, .{ .Int, .ComptimeInt });
    return int_a & (int_b - 1);
}

test fastMod {}

/// Retrieve 10 to the power of `exp`.
/// Interface for 'power\_of\_10\_table_...'.
/// Compute - very cheap, direct array indexing.
pub inline fn indexPower10(exp: u4, comptime typ: enum { Float, Int }) if (typ == .Float) f64 else u64 {
    switch (typ) { // * comptime branch prune
        .Float => return power_of_10_table_float[exp],
        .Int => return power_of_10_table_int[exp],
    }
}

test indexPower10 {
    try expectEqual(1_0000, indexPower10(4, .Int));
    try expectEqual(1_0000.0, indexPower10(4, .Float));
}

/// Powers of 10 lookup table (float).
/// Size: 16 entries * 8 bytes = 128 bytes.
/// { 1.0, 10.0, 100.0, 1000.0, ..., 10 ^ 15 }
pub const power_of_10_table_float = blk: {
    const len = 16;
    var buf: [len]f64 = undefined;
    buf[0] = 1;
    for (1..len) |i| buf[i] = buf[i - 1] * 10;
    break :blk buf;
};

test power_of_10_table_float {
    try expectEqual(1.0, power_of_10_table_float[0]);
    try expectEqual(1_000_000_000_000_000.0, power_of_10_table_float[15]);
}

/// Powers of 10 lookup table (int).
/// Size: 16 entries * 8 bytes = 128 bytes.
/// { 1, 10, 100, 1000, ..., 10 ^ 15 }
pub const power_of_10_table_int = blk: {
    const len = 16;
    var buf: [len]u64 = undefined;
    buf[0] = 1;
    for (1..len) |i| buf[i] = buf[i - 1] * 10;
    break :blk buf;
};

test power_of_10_table_int {
    try expectEqual(1, power_of_10_table_int[0]);
    try expectEqual(1_000_000_000_000_000, power_of_10_table_int[15]);
}
