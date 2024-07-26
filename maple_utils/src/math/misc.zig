//! Author: palsmo
//! Status: In Progress

const std = @import("std");
const math = std.math;

const maple_typ = @import("../typ/root.zig");
const root_shared = @import("./shared.zig");

const Error = root_shared.Error;
const assertType = maple_typ.assertType;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Assert that `int` is some power of two.
pub inline fn assertPowOf2(int: anytype) void {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt }, @src().fn_name ++ ".int");
    if (isPowOf2(int)) return;
    panic("Value is not a power of two, found '{}'", .{int});
}

/// Fast `a` modulus `b`, but `b` has to be a power of two.
/// Computation | very cheap
pub inline fn fastMod(comptime T: type, a: T, b: T) void {
    return a & (b - 1);
}

/// Check if `int` is some power of two.
/// Computation | very cheap
pub inline fn isPowOf2(int: anytype) bool {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt }, @src().fn_name ++ ".int");
    // * powers of 2 only has one bit set
    return int != 0 and (int & (int - 1)) == 0;
}

test isPowOf2 {
    try expectEqual(true, isPowOf2(2));
    try expectEqual(false, isPowOf2(3));
}

/// Retrieve 10 to the power of `exp`.
/// Interface for 'power\_of\_10\_table_...'.
/// Computation | very cheap
pub inline fn getPow10(exp: u4, comptime typ: enum { Float, Int }) if (typ == .Float) f64 else u64 {
    switch (typ) {
        .Float => return power_of_10_table_float[exp],
        .Int => return power_of_10_table_int[exp],
    }
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

/// Multiply some percentage `percentage_float` with some number `n`.
/// Useful for calculating tresholds for (u)sizes and similar.
/// Adjust precision of `percent_float` by number of decimal places with `options.precision`.
/// Asserts that `percent_float` is within range [0.0, 1.0] (* overflow error gets avoided).
/// Computation | cheap
pub fn mulPercent(percent_float: f64, n: usize, options: struct { precision: u4 = 2 }) usize {
    // checking `percent_float`
    if (!math.isFinite(percent_float) or percent_float < 0.0 or percent_float > 1.0) {
        panic("Invalid percentage, found '{d}'", .{percent_float});
    }

    // convert percentage to fixed-point
    const precision_p10_float: f64 = getPow10(options.precision, .Float);
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, n) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = getPow10(options.precision, .Int);
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

    // test large `n`
    const max_usize = math.maxInt(usize);
    try expectEqual(max_usize, mulPercent(1.0, max_usize, .{}));
    try expectEqual((max_usize + 1) / 2, mulPercent(0.5, max_usize, .{}));
}

/// Returns an incremented `num`, wrapping according to [`min`, `max`).
pub inline fn wrapIncrement(comptime T: type, num: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat }, @src().fn_name ++ ".T");
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
pub inline fn wrapDecrement(comptime T: type, value: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat }, @src().fn_name ++ ".T");
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
