//! Author: palsmo
//! Status: In Progress
//! Brief: Miscellaneous Mathematical Operations

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_type = @import("../type/root.zig");
const root_float = @import("./float.zig");
const root_int = @import("./int.zig");

const assertType = mod_assert.assertType;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

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
    const precision_p10_float: f64 = root_float.POWER_OF_10_TABLE[options.precision];
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, num) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = root_int.POWER_OF_10_TABLE[options.precision];
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
