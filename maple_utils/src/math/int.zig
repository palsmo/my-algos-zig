//! Author: palsmo
//! Status: In Progress
//! Brief: Integer Numeric Functionality

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_type = @import("../type/root.zig");
const root_misc = @import("./misc.zig");

const TInt = mod_type.TInt;
const ValueError = prj.errors.ValueError;
const assertType = mod_assert.assertType;
const assertTypeSame = mod_assert.assertTypeSame;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Powers of 10 lookup table.
/// Size: 16 entries * 8 bytes = 128 bytes.
/// { 1, 10, 100, 1000, ..., 10 ^ 15 }
pub const POWER_OF_10_TABLE = b: {
    const len = 16;
    var buf: [len]u64 = undefined;
    buf[0] = 1;
    for (1..len) |i| buf[i] = buf[i - 1] * 10;
    break :b buf;
};

test POWER_OF_10_TABLE {
    try expectEqual(1, POWER_OF_10_TABLE[0]);
    try expectEqual(1_000_000_000_000_000, POWER_OF_10_TABLE[15]);
}

pub fn max(comptime T: type) comptime_int {
    comptime assertType(T, .{.int});
    const info = @typeInfo(T);
    var bit_count = info.int.bits;
    if (bit_count == 0) return 0;
    bit_count -= @intFromBool(info.int.signedness == .signed);
    return (1 << (bit_count)) - 1;
}

test max {
    try expectEqual(255, max(u8));
    try expectEqual(127, max(i8));
}

pub fn min(comptime T: type) comptime_int {
    comptime assertType(T, .{.int});
    const info = @typeInfo(T);
    const bit_count = info.int.bits;
    if (info.int.signedness == .unsigned) return 0;
    if (bit_count == 0) return 0;
    return -(1 << (bit_count - 1));
}

test min {
    try expectEqual(0, min(u8));
    try expectEqual(-128, min(i8));
}

/// Returns the sum of `int_a` + `int_b`.
/// Asserts `int_a` and `int_b` to be the same *integer* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *Overflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedAdd(int_a: anytype, int_b: anytype) ValueError!@TypeOf(int_a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(int_a), @TypeOf(int_b));
    comptime assertType(@TypeOf(int_a), .{ .int, .comptime_int });

    const T_int = @TypeOf(int_a);

    switch (T_int) { // * comptime prune
        comptime_int => return int_a + int_b,
        else => {
            const result = @addWithOverflow(int_a, int_b);
            return if (result[1] == 0) result[0] else error.Overflow;
        },
    }
}

test checkedAdd {
    // ok
    try expectEqual(7, checkedAdd(@as(u8, 4), @as(u8, 3)));
    try expectEqual(1, checkedAdd(@as(i8, 4), @as(i8, -3)));
    // issue
    try expectEqual(error.Overflow, checkedAdd(@as(u8, 128), @as(u8, 128)));
    try expectEqual(error.Overflow, checkedAdd(@as(i8, 64), @as(i8, 64)));
}

/// Returns the product of `int_a` * `int_b`.
/// Asserts `int_a` and `int_b` to be the same *integer* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *Overflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedMul(int_a: anytype, int_b: anytype) ValueError!@TypeOf(int_a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(int_a), @TypeOf(int_b));
    comptime assertType(@TypeOf(int_a), .{ .int, .comptime_int });

    const T_int = @TypeOf(int_a);

    switch (T_int) { // * comptime prune
        comptime_int => return int_a * int_b,
        else => {
            const result = @mulWithOverflow(int_a, int_b);
            return if (result[1] == 0) result[0] else error.Overflow;
        },
    }
}

test checkedMul {
    // ok
    try expectEqual(12, checkedMul(@as(u8, 4), @as(u8, 3)));
    try expectEqual(-12, checkedMul(@as(i8, 4), @as(i8, -3)));
    // issue
    try expectError(error.Overflow, checkedMul(@as(u8, 16), @as(u8, 16)));
    try expectEqual(error.Overflow, checkedMul(@as(i8, 16), @as(i8, 8)));
}

/// Returns the difference of `a` - `b`.
/// Asserts `a` and `b` to be the same *integer* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *Underflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedSub(int_a: anytype, int_b: anytype) ValueError!@TypeOf(int_a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(int_a), @TypeOf(int_b));
    comptime assertType(@TypeOf(int_a), .{ .int, .comptime_int });

    const T_int = @TypeOf(int_a);

    switch (T_int) { // * comptime prune
        comptime_int => return int_a - int_b,
        else => {
            const result = @subWithOverflow(int_a, int_b);
            return if (result[1] == 0) result[0] else error.Underflow;
        },
    }
}

test checkedSub {
    // ok
    try expectEqual(1, checkedSub(@as(u8, 4), @as(u8, 3)));
    try expectEqual(7, checkedSub(@as(i8, 4), @as(i8, -3)));
    // issue
    try expectError(error.Underflow, checkedSub(@as(u8, 1), @as(u8, 2)));
    try expectError(error.Underflow, checkedSub(@as(i8, -128), @as(i8, 1)));
}

/// Fast `int_a` modulus `int_b`, but `int_b` has to be a power of two.
/// Asserts `int_a` and `int_b` to be the same *integer* type.
/// Compute - *very cheap*, two basic operations.
pub inline fn fastMod(int_a: anytype, int_b: anytype) @TypeOf(int_a) {
    comptime assertTypeSame(@TypeOf(int_a), @TypeOf(int_b));
    comptime assertType(@TypeOf(int_a), .{ .int, .comptime_int });

    return int_a & (int_b - 1);
}

test fastMod {
    try expectEqual(2, fastMod(2, 4));
    try expectEqual(0, fastMod(4, 4));
    try expectEqual(2, fastMod(6, 4));
    try expectEqual(0, fastMod(8, 4));
}

/// Check if `int` is some power of two.
/// Asserts `int` to be an *integer* type.
/// Compute - *very cheap*, comparison, subtraction and bit-operation.
pub inline fn isPowerOf2(int: anytype) bool {
    comptime assertType(@TypeOf(int), .{ .int, .comptime_int });
    return int > 0 and (int & (int - 1)) == 0; // * powers of 2 only has one bit set
}

test isPowerOf2 {
    try expectEqual(true, isPowerOf2(4));
    try expectEqual(true, isPowerOf2(2));
    try expectEqual(true, isPowerOf2(1));
    //
    try expectEqual(false, isPowerOf2(3));
    try expectEqual(false, isPowerOf2(0));
    try expectEqual(false, isPowerOf2(-1));
}

/// Returns the next power of two (equal or greater than `int`).
/// Asserts `int` to be an *integer* type.
/// Compute - *very cheap*, few basic and specific operations.
/// Issue key specs:
/// TODO, complete this \/
/// - Throws *Overflow* when result would overflow `@TypeOf(num)`.
pub fn nextPowerOf2(int: anytype) ValueError!@TypeOf(int) {
    comptime assertType(@TypeOf(int), .{ .int, .comptime_int });

    if (int <= 1) return 1;

    const T_int = @TypeOf(int);
    switch (@typeInfo(T_int)) { // * comptime prune
        .int => |info| {
            const shift = info.bits - @as(u16, @clz(int - 1));
            switch (info.signedness) { // * comptime prune
                .unsigned => if (shift >= info.bits) return error.Overflow,
                .signed => if (shift >= info.bits - 1) return error.Overflow,
            }
            return @as(T_int, 1) << @intCast(shift);
        },
        .comptime_int => {
            const _bits = root_misc.minRepBits(int);
            const _value: TInt(.unsigned, _bits) = int;
            const shift = _bits - @clz(_value - 1);
            return 1 << shift;
        },
        else => unreachable,
    }
}

test nextPowerOf2 {
    // greater
    try expectEqual(4, nextPowerOf2(@as(u8, 3)));
    try expectEqual(4, nextPowerOf2(@as(i8, 3)));
    try expectEqual(4, nextPowerOf2(@as(comptime_int, 3.0)));
    // equal
    try expectEqual(2, nextPowerOf2(@as(u8, 2)));
    try expectEqual(2, nextPowerOf2(@as(i8, 2)));
    try expectEqual(2.0, nextPowerOf2(@as(comptime_int, 2.0)));
    // edge cases
    try expectEqual(1, nextPowerOf2(@as(u8, 0)));
    try expectError(error.Overflow, nextPowerOf2(@as(u8, 255)));
    //
    try expectEqual(1, nextPowerOf2(@as(i8, 0)));
    try expectEqual(1, nextPowerOf2(@as(i8, -1)));
    try expectError(error.Overflow, nextPowerOf2(@as(i8, 127)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, -1.0)));
}

/// Retrieve 10 to the power of `exp`.
/// Compute - *very cheap*/*cheap*, direct array indexing, linear flow.
/// Issue key specs:
/// - Throws *Overflow* when result overflows `u64`.
pub inline fn nthPower10(exp: u8) ValueError!u64 {
    const tab_len = POWER_OF_10_TABLE.len;
    const in_table = (exp < tab_len);
    if (in_table) {
        return POWER_OF_10_TABLE[exp];
    } else {
        const ret = POWER_OF_10_TABLE[exp];
        var rest = exp - (tab_len - 1);
        while (rest > 0) : (rest -= 1) {
            const result = @mulWithOverflow(ret, 10);
            if (result[1] != 0) return error.Overflow;
            ret += result[0];
        }
        return ret;
    }
}

test nthPower10 {
    try expectEqual(10_000, nthPower10(4));
    try expectEqual(1e64, nthPower10(64));
    try expectError(error.Overflow, nthPower10(65));
}

/// Returns number of minimum bits needed to represent `int`.
/// Asserts `int` to be an *integer* type.
/// Compute - *very cheap*, few basic operations.
pub fn minRepBits(int: anytype) u16 {
    comptime assertType(@TypeOf(int), .{ .int, .comptime_int });

    const abs_int = if (int >= 0) int else -int;
    if (abs_int == 0) return 1;

    const T_int = @TypeOf(int);
    return switch (T_int) { // * comptime prune
        comptime_int => std.math.log2(abs_int) + 1 + @as(u16, @intFromBool(int < 0)),
        else => @bitSizeOf(T_int) - @as(u16, @clz(abs_int)) + @as(u16, @intFromBool(int < 0)),
    };
}

test minRepBits {
    try expectEqual(1, minRepBits(@as(u8, 0)));
    try expectEqual(2, minRepBits(@as(u8, 2)));
    try expectEqual(2, minRepBits(@as(i8, -1)));
    try expectEqual(1, minRepBits(@as(comptime_int, 0)));
    try expectEqual(2, minRepBits(@as(comptime_int, 2)));
    try expectEqual(2, minRepBits(@as(comptime_int, -1)));
}
