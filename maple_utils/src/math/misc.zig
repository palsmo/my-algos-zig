//! Author: palsmo
//! Status: In Progress
//! Brief: Miscellaneous Mathematical Operations

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_type = @import("../type/root.zig");
const root_float = @import("./float.zig");

const TInt = mod_type.misc.TInt;
const ValueError = prj.errors.ValueError;
const assertType = mod_assert.assertType;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const panic = std.debug.panic;

/// Powers of 10 lookup table (float).
/// Size: 16 entries * 8 bytes = 128 bytes.
/// { 1.0, 10.0, 100.0, 1000.0, ..., 10 ^ 15 }
pub const POWER_OF_10_TABLE_FLOAT = b: {
    const len = 16;
    var buf: [len]f64 = undefined;
    buf[0] = 1;
    for (1..len) |i| buf[i] = buf[i - 1] * 10;
    break :b buf;
};

test POWER_OF_10_TABLE_FLOAT {
    try expectEqual(1.0, POWER_OF_10_TABLE_FLOAT[0]);
    try expectEqual(1_000_000_000_000_000.0, POWER_OF_10_TABLE_FLOAT[15]);
}

/// Powers of 10 lookup table (int).
/// Size: 16 entries * 8 bytes = 128 bytes.
/// { 1, 10, 100, 1000, ..., 10 ^ 15 }
pub const POWER_OF_10_TABLE_INT = b: {
    const len = 16;
    var buf: [len]u64 = undefined;
    buf[0] = 1;
    for (1..len) |i| buf[i] = buf[i - 1] * 10;
    break :b buf;
};

test POWER_OF_10_TABLE_INT {
    try expectEqual(1, POWER_OF_10_TABLE_INT[0]);
    try expectEqual(1_000_000_000_000_000, POWER_OF_10_TABLE_INT[15]);
}

/// Retrieve 10 to the power of `exp`.
/// Interface for 'power\_of\_10\_table_...'.
/// Compute - *very cheap*, direct array indexing.
pub inline fn indexPower10(exp: u4, comptime typ: enum { float, int }) if (typ == .float) f64 else u64 {
    switch (typ) { // * comptime branch prune
        .float => return POWER_OF_10_TABLE_FLOAT[exp],
        .int => return POWER_OF_10_TABLE_INT[exp],
    }
}

test indexPower10 {
    try expectEqual(1_0000, indexPower10(4, .int));
    try expectEqual(1_0000.0, indexPower10(4, .float));
}

/// Returns bits needed to represent `int`.
/// Asserts `int` to be an *int* type.
/// Compute - *very cheap*, few basic operations.
pub fn minBits(int: anytype) u16 {
    comptime assertType(@TypeOf(int), .{ .int, .comptime_int });

    const abs_int = if (int >= 0) int else -int;
    if (abs_int == 0) return 1;

    const T_int = @TypeOf(int);
    return switch (T_int) { // * comptime prune
        comptime_int => std.math.log2(abs_int) + 1 + @as(u16, @intFromBool(int < 0)),
        else => @bitSizeOf(T_int) - @as(u16, @clz(abs_int)) + @as(u16, @intFromBool(int < 0)),
    };
}

test minBits {
    try expectEqual(1, minBits(@as(u8, 0)));
    try expectEqual(2, minBits(@as(u8, 2)));
    try expectEqual(2, minBits(@as(i8, -1)));
    try expectEqual(1, minBits(@as(comptime_int, 0)));
    try expectEqual(2, minBits(@as(comptime_int, 2)));
    try expectEqual(2, minBits(@as(comptime_int, -1)));
}

/// Returns the next power of two (equal or greater than `num`).
/// Asserts `num` to be a *numeric* type.
/// Compute - *very cheap*, few basic and specific operations.
/// Issue key specs:
/// TODO, complete this \/
/// - Throws *Overflow* when result would overflow `@TypeOf(num)`.
pub fn nextPowerOf2(num: anytype) ValueError!@TypeOf(num) {
    assertType(@TypeOf(num), .{ .int, .float, .comptime_int, .comptime_float });

    if (num <= 1) return 1;

    const T_num = @TypeOf(num);
    switch (@typeInfo(T_num)) { // * comptime prune
        .int => |info| {
            const shift = info.bits - @as(u16, @clz(num - 1));
            switch (info.signedness) { // * comptime prune
                .unsigned => if (shift >= info.bits) return error.Overflow,
                .signed => if (shift >= info.bits - 1) return error.Overflow,
            }
            return @as(T_num, 1) << @intCast(shift);
        },
        .comptime_int => {
            const _bits = minBits(num);
            const _value: TInt(.unsigned, _bits) = num;
            const shift = _bits - @clz(_value - 1);
            return 1 << shift;
        },
        .float => {
            if (!root_float.isFinite(num)) return error.UnableToHandle;
            const result = @exp2(@ceil(@log2(num)));
            if (root_float.isInf(result, .positive)) return error.Overflow;
            return result;
        },
        .comptime_float => return @exp2(@ceil(@log2(num))),
        else => unreachable,
    }
}

test nextPowerOf2 {
    // greater
    try expectEqual(4, nextPowerOf2(@as(u8, 3)));
    try expectEqual(4, nextPowerOf2(@as(i8, 3)));
    try expectEqual(4.0, nextPowerOf2(@as(f16, 3.0)));
    try expectEqual(4, nextPowerOf2(@as(comptime_int, 3.0)));
    try expectEqual(4.0, nextPowerOf2(@as(comptime_float, 3.0)));
    // equal
    try expectEqual(2, nextPowerOf2(@as(u8, 2)));
    try expectEqual(2, nextPowerOf2(@as(i8, 2)));
    try expectEqual(2.0, nextPowerOf2(@as(f16, 2.0)));
    try expectEqual(2.0, nextPowerOf2(@as(comptime_int, 2.0)));
    try expectEqual(2.0, nextPowerOf2(@as(comptime_float, 2.0)));
    // edge cases
    try expectEqual(1, nextPowerOf2(@as(u8, 0)));
    try expectError(error.Overflow, nextPowerOf2(@as(u8, 255)));
    //
    try expectEqual(1, nextPowerOf2(@as(i8, 0)));
    try expectEqual(1, nextPowerOf2(@as(i8, -1)));
    try expectError(error.Overflow, nextPowerOf2(@as(i8, 127)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(f16, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(f16, -1.0)));
    try expectError(error.Overflow, nextPowerOf2(root_float.max(f16)));
    try expectError(error.UnableToHandle, nextPowerOf2(root_float.inf(f16, .positive)));
    try expectError(error.UnableToHandle, nextPowerOf2(root_float.nan(f16, .positive, .quiet)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, -1.0)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(comptime_float, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_float, -1.0)));
}

/// Check if `int` is some power of two.
/// Asserts `int` to be an *int* type.
/// Compute - *very cheap*, comparison, subtraction and bit-operation.
pub inline fn isPowerOf2(int: anytype) bool {
    comptime assertType(@TypeOf(int), .{ .int, .comptime_int });
    return int != 0 and (int & (int - 1)) == 0; // * powers of 2 only has one bit set
}

test isPowerOf2 {
    try expectEqual(false, isPowerOf2(0));
    try expectEqual(true, isPowerOf2(1));
    try expectEqual(true, isPowerOf2(2));
    try expectEqual(false, isPowerOf2(3));
}

/// Multiply some percentage `percentage_float` with some number `n`.
/// Useful for calculating tresholds for (u)sizes and similar.
/// Adjust precision of `percent_float` by number of decimal places with `options.precision`.
/// Asserts that `percent_float` is within range [0.0, 1.0] (* overflow error is avoided).
/// Compute - *cheap*, multiplication, division, few type conversions.
pub fn mulPercent(percent_float: f64, num: usize, options: struct { precision: u4 = 2 }) usize {
    // checking `percent_float`
    if (!root_float.isFinite(percent_float) or percent_float < 0.0 or percent_float > 1.0) {
        panic("Invalid percentage, found '{d}'", .{percent_float});
    }

    // convert percentage to fixed-point
    const precision_p10_float: f64 = indexPower10(options.precision, .float);
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, num) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = indexPower10(options.precision, .int);
    const result_round: u128 = result_full + (precision_p10_int / 2);
    const result: u128 = result_round / precision_p10_int;

    return @intCast(result);
}

test mulPercent {
    // test basic
    try expectEqual(@as(usize, 3), mulPercent(0.3, 10, .{}));
    try expectEqual(@as(usize, 10), mulPercent(1.0, 10, .{}));
    // test edge cases
    try expectEqual(@as(usize, 0), mulPercent(0.5, 0, .{}));
    try expectEqual(@as(usize, 0), mulPercent(0.0, 10, .{}));
    // test rounding
    try expectEqual(@as(usize, 3), mulPercent(0.33, 10, .{}));
    try expectEqual(@as(usize, 7), mulPercent(0.66, 10, .{}));
    // test precision
    try expectEqual(@as(usize, 0), mulPercent(0.9, 100, .{ .precision = 0 }));
    try expectEqual(@as(usize, 100), mulPercent(1.0, 100, .{ .precision = 0 }));
    try expectEqual(@as(usize, 4_567), mulPercent(0.4567, 10_000, .{ .precision = 4 }));
    // test large inputs
    const max_usize = std.math.maxInt(usize);
    try expectEqual(max_usize, mulPercent(1.0, max_usize, .{}));
    try expectEqual((max_usize + 1) / 2, mulPercent(0.5, max_usize, .{}));
    try expectEqual(max_usize, mulPercent(1.0, max_usize, .{ .precision = 15 }));
}

/// Returns an incremented `num`, wrapping according to [`min`, `max`).
/// Incorrect behavior when `min` > `max`.
/// Asserts `T` to be a *numeric* type.
/// Compute - *very cheap*, single addition and comparison.
/// Issue key specs:
/// TODO, complete this \/
/// - Panics when `num` would overflow `T` from increment (only *integer* + @setRuntimeSafety(true)).
pub inline fn wrapIncrement(comptime T: type, num: T, min: T, max: T) T {
    assertType(T, .{ .int, .float, .comptime_int, .comptime_float });
    const _num = if (@typeInfo(T) == .int) num +% 1 else num + 1; // * comptime prune
    return if (_num < max) _num else min;
}

test wrapIncrement {
    // general
    try expectEqual(3, wrapIncrement(u8, 2, 0, 4));
    try expectEqual(0, wrapIncrement(u8, 3, 0, 4));
    try expectEqual(-1, wrapIncrement(i8, -2, -4, 4));
    try expectEqual(3.0, wrapIncrement(f16, 2.0, 0.0, 4.0));
    // edge cases
    try expectEqual(0, wrapIncrement(u8, 254, 0, 255)); // full range
    //try expectEqual(4, wrapIncrement(u8, 1, 4, 3)); // min > max
    // *inf* and *nan* expected logic
}

/// Returns a decremented `num`, wrapping according to [`min`, `max`).
/// Incorrect behavior when `min` > `max`.
/// Asserts `T` to be a *numeric* type.
/// Compute - *very cheap*, single comparison and subtraction.
/// Issue key specs:
/// Panics when `max` would underflow `T` from decrement (only *integer* + @setRuntimeSafety(true)).
pub inline fn wrapDecrement(comptime T: type, num: T, min: T, max: T) T {
    assertType(T, .{ .int, .float, .comptime_int, .comptime_float });
    return if (num > min) num - 1 else max - 1;
}

test wrapDecrement {
    // general
    try expectEqual(2, wrapDecrement(u8, 3, 0, 4));
    try expectEqual(3, wrapDecrement(u8, 0, 0, 4));
    try expectEqual(-1, wrapDecrement(i8, 0, -2, 4));
    try expectEqual(2.0, wrapDecrement(f16, 3.0, 0.0, 4.0));
    // edge cases
    try expectEqual(254, wrapDecrement(u8, 0, 0, 255)); // full range
    try expectEqual(2, wrapDecrement(u8, 1, 4, 3)); // min > max
    // try expectEqual(!, wrapDecrement(u8, 0, 0, 0)); * can't test panic
    // *inf* and *nan* expected logic
}

////pub fn entropy() f64 {}
//
////pub fn entropyDynAlloc() f64 {}
//
///// Calculates the randomness of given `data`.
///// Uses "Shannon's entropy formula".
//pub fn entropyPreAlloc(comptime T: type, data: []const T) f64 {
//    //const bytes = if (T == u8) data else std.mem.asBytes(data);
//    const max_size = @sizeOf(T);
//    const len = @min(
//    var counts: [max_value]data.len = [_]usize{0} ** max_value;
//
//    // Count occurrences of each unique value
//    for (data) |item| {
//        counts[@intCast(usize, item)] += 1;
//    }
//
//    var entropy: f64 = 0;
//    const n = @intToFloat(f64, data.len);
//
//    // Calculate entropy using Shannon's formula
//    for (counts) |count| {
//        if (count > 0) {
//            const p = @intToFloat(f64, count) / n;
//            entropy -= p * math.log2(p);
//        }
//    }
//
//    return entropy;
//}
//
///// Normalize entropy constant `x` -> [0.0..1.0]
//pub fn normal(x: f64) f16 {
//    _ = x;
//}
//
///// Name space with some contexts.
//const context = struct {
//    const bytes = struct {
//        inline fn eql(a: []const u8, b: []const u8) bool {
//            return @call(.always_inline, std.mem.eql, .{ u8, a, b});
//        }
//    };
//};
//
////const result = entropy.calc(u8, items);
////const result_normal = entropy.normal(result);
