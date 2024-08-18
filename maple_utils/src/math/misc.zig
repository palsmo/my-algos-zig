//! Author: palsmo
//! Status: In Progress
//! About: Miscellaneous Mathematical Operations

const std = @import("std");
const math = std.math;

const proj_shared = @import("../../../shared.zig");
const mod_assert = @import("../assert/root.zig");
const root_shared = @import("./shared.zig");
const root_prim = @import("./primitive.zig");

const ValueError = root_shared.ValueError;
const assertType = mod_assert.misc.assertType;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const panic = std.debug.panic;

/// Returns bits needed to represent `int`.
/// Asserts `int` to be an integer.
/// Compute - very cheap, few basic operations.
pub fn bitsNeeded(int: anytype) u16 {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt });

    const abs_int = if (int >= 0) int else -int;
    if (abs_int == 0) return 1;

    const T_int = @TypeOf(int);
    return switch (@typeInfo(T_int)) { // * comptime branch prune
        .Int => @bitSizeOf(T_int) - @as(u16, @clz(abs_int)) + @as(u16, @intFromBool(int < 0)),
        .ComptimeInt => std.math.log2(abs_int) + 1 + @as(u16, @intFromBool(int < 0)),
        else => unreachable,
    };
}

test bitsNeeded {
    try expectEqual(1, bitsNeeded(@as(u8, 0)));
    try expectEqual(2, bitsNeeded(@as(u8, 2)));
    try expectEqual(2, bitsNeeded(@as(i8, -1)));
    try expectEqual(1, bitsNeeded(@as(comptime_int, 0)));
    try expectEqual(2, bitsNeeded(@as(comptime_int, 2)));
    try expectEqual(2, bitsNeeded(@as(comptime_int, -1)));
}

/// Returns the next power of two (equal or greater than `int`).
/// Asserts `num` to be a numeric type.
/// Compute - very cheap, few basic and specific operations.
pub fn nextPowerOf2(num: anytype) !@TypeOf(num) {
    comptime assertType(@TypeOf(num), .{ .Int, .Float, .ComptimeFloat, .ComptimeInt });

    if (num <= 1) return 1;

    const T_num = @TypeOf(num);
    switch (@typeInfo(T_num)) { // * comptime branch prune
        .Int => |info| {
            const shift = info.bits - @as(u16, @clz(num - 1));
            switch (info.signedness) { // * comptime branch prune
                .unsigned => if (shift >= info.bits) return ValueError.Overflow,
                .signed => if (shift >= info.bits - 1) return ValueError.Overflow,
            }
            return @as(T_num, 1) << @intCast(shift);
        },
        .ComptimeInt => {
            const _bits = bitsNeeded(num);
            const _value: std.meta.Int(.unsigned, _bits) = num;
            const shift = _bits - @clz(_value - 1);
            return 1 << shift;
        },
        .Float => {
            if (!std.math.isFinite(num)) return ValueError.UnableToHandle;
            const result = @exp2(@ceil(@log2(num)));
            if (std.math.isPositiveInf(result)) return ValueError.Overflow;
            return result;
        },
        .ComptimeFloat => return @exp2(@ceil(@log2(num))),
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
    try expectError(ValueError.Overflow, nextPowerOf2(@as(u8, 255)));
    //
    try expectEqual(1, nextPowerOf2(@as(i8, 0)));
    try expectEqual(1, nextPowerOf2(@as(i8, -1)));
    try expectError(ValueError.Overflow, nextPowerOf2(@as(i8, 127)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(f16, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(f16, -1.0)));
    try expectError(ValueError.Overflow, nextPowerOf2(std.math.floatMax(f16)));
    try expectError(ValueError.UnableToHandle, nextPowerOf2(std.math.inf(f16)));
    try expectError(ValueError.UnableToHandle, nextPowerOf2(std.math.nan(f16)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_int, -1.0)));
    //
    try expectEqual(1.0, nextPowerOf2(@as(comptime_float, 0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_float, -1.0)));
}

/// Check if `int` is some power of two.
/// Asserts `int` to be an integer.
/// Compute - very cheap, comparison, subtraction and bit-operation.
pub inline fn isPowerOf2(int: anytype) bool {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt });
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
/// Compute - cheap, multiplication, division, few type conversions.
pub fn mulPercent(percent_float: f64, num: usize, options: struct { precision: u4 = 2 }) usize {
    // checking `percent_float`
    if (!math.isFinite(percent_float) or percent_float < 0.0 or percent_float > 1.0) {
        panic("Invalid percentage, found '{d}'", .{percent_float});
    }

    // convert percentage to fixed-point
    const precision_p10_float: f64 = root_prim.indexPower10(options.precision, .Float);
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, num) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = root_prim.indexPower10(options.precision, .Int);
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
    const max_usize = math.maxInt(usize);
    try expectEqual(max_usize, mulPercent(1.0, max_usize, .{}));
    try expectEqual((max_usize + 1) / 2, mulPercent(0.5, max_usize, .{}));
    try expectEqual(max_usize, mulPercent(1.0, max_usize, .{ .precision = 15 }));
}

/// Returns an incremented `num`, wrapping according to [`min`, `max`).
/// Asserts `T` to be an integer or float.
/// Compute - very cheap, single addition and comparison.
pub inline fn wrapIncrement(comptime T: type, num: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat });
    const new_num = num + 1;
    return if (new_num < max) new_num else min;
}

test wrapIncrement {
    try expectEqual(@as(u8, 0), wrapIncrement(u8, 3, 0, 4));
    try expectEqual(@as(i8, -1), wrapIncrement(i8, 3, -1, 4));
    try expectEqual(@as(f16, 1.0), wrapIncrement(f16, 3.0, 1.0, 4.0));
    try expectEqual(@as(u8, 2), wrapIncrement(u8, 1, 0, 4)); // non-wrap case
}

/// Returns a decremented `value`, wrapping according to [`min`, `max`).
/// Asserts `T` to be an integer or float.
/// Compute - very cheap, single comparison and subtraction.
pub inline fn wrapDecrement(comptime T: type, value: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat });
    return if (min < value) value - 1 else max - 1;
}

test wrapDecrement {
    try expectEqual(@as(u8, 3), wrapDecrement(u8, 0, 0, 4));
    try expectEqual(@as(i8, 3), wrapDecrement(i8, -1, -1, 4));
    try expectEqual(@as(f16, 3.0), wrapDecrement(f16, 1.0, 1.0, 4.0));
    try expectEqual(@as(u8, 2), wrapDecrement(u8, 3, 0, 4)); // non-wrap case
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
