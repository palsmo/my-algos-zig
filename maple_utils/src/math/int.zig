//! Author: palsmo
//! Status: Done
//! Brief: Integer Numeric Functionality

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");

const ValueError = prj.errors.ValueError;
const assertType = mod_assert.assertType;
const assertTypeSame = mod_assert.assertTypeSame;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

/// Returns the sum of `a` + `b`.
/// Asserts `a` and `b` to be the same *integer* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *.Overflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedAdd(a: anytype, b: anytype) ValueError!@TypeOf(a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{ .int, .comptime_int });

    const T_int = @TypeOf(a);

    switch (T_int) { // * comptime prune
        comptime_int => return a + b,
        else => {
            const result = @addWithOverflow(a, b);
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

/// Returns the product of `a` * `b`.
/// Asserts `a` and `b` to be the same *integer* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *.Overflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedMul(a: anytype, b: anytype) ValueError!@TypeOf(a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{ .int, .comptime_int });

    const T_int = @TypeOf(a);

    switch (T_int) { // * comptime prune
        comptime_int => return a * b,
        else => {
            const result = @mulWithOverflow(a, b);
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
/// - Throws *.Underflow* when result overflows `@TypeOf(a)`.
pub inline fn checkedSub(a: anytype, b: anytype) ValueError!@TypeOf(a) {
    @setRuntimeSafety(false); // (asm) ignore testing of-flag twice (ReleaseSafe)
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{ .int, .comptime_int });

    const T_int = @TypeOf(a);

    switch (T_int) { // * comptime prune
        comptime_int => return a - b,
        else => {
            const result = @subWithOverflow(a, b);
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

/// Fast `a` modulus `b`, but `b` has to be a power of two.
/// Asserts `a` and `b` to be the same *integer* type.
/// Compute - *very cheap*, two basic operations.
pub inline fn fastMod(a: anytype, b: anytype) @TypeOf(a) {
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{ .int, .comptime_int });

    return a & (b - 1);
}

test fastMod {}
