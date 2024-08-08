//! Author: palsmo
//! Status: In Progress

const std = @import("std");
const math = std.math;

const mod_assert = @import("../assert/root.zig");
const root_shared = @import("./shared.zig");

const ValueError = root_shared.ValueError;
const assertType = mod_assert.misc.assertType;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const panic = std.debug.panic;

/// Returns the sum of `a` + `b`.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeAdd(comptime T: type, a: T, b: T) !T {
    comptime assertType(T, .{ .Int, .ComptimeInt }, "fn {s}.T", .{@src().fn_name});
    if (T == comptime_int) return a * b;
    const result = @addWithOverflow(a, b);
    switch (result[1]) {
        0 => return result[0],
        1 => return ValueError.Overflow,
    }
}

test safeAdd {
    try expectEqual(7, safeAdd(u8, 3, 4));
    try expectError(ValueError.Overflow, safeAdd(u8, 128, 128));
}

/// Returns the product of `a` * `b`.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeMul(comptime T: type, a: T, b: T) !T {
    comptime assertType(T, .{ .Int, .ComptimeInt }, "fn {s}.T", .{@src().fn_name});
    if (T == comptime_int) return a * b;
    const result = @mulWithOverflow(a, b);
    switch (result[1]) {
        0 => return result[0],
        1 => return ValueError.Overflow,
    }
}

test safeMul {
    try expectEqual(6, safeMul(u8, 2, 3));
    try expectError(ValueError.Overflow, safeMul(u8, 16, 16));
}

/// Returns the difference of `a` - `b`.
/// Issue key specs:
/// - Throws error when result would overflow `T`.
pub inline fn safeSub(comptime T: type, a: T, b: T) !T {
    comptime assertType(T, .{ .Int, .ComptimeInt }, "fn {s}.T", .{@src().fn_name});
    if (T == comptime_int) return a - b;
    const result = @subWithOverflow(a, b);
    switch (result[1]) {
        0 => return result[0],
        1 => return ValueError.Overflow,
    }
}

test safeSub {
    try expectEqual(4, safeSub(u8, 8, 4));
    try expectError(ValueError.Overflow, safeSub(u8, 4, 8));
}

/// Returns an integer type that can hold value `n`.
/// Takes .{ .Int, .Float, .ComptimeInt, .ComptimFloat } as `n`.
pub fn IntFromAnyNumeric(comptime n: anytype, comptime mode: enum { Smallest, PowerOf2 }) type {
    comptime assertType(@TypeOf(n), .{ .Int, .Float, .ComptimeInt, .ComptimeFloat }, "fn {s}.n", @src().fn_name);

    const n_abs, const signedness = b: {
        switch (@typeInfo(@TypeOf(n))) {
            .Int => |info| {
                const abs_int = if (n >= 0) n else -n;
                const signedness = info.signedness;
                break :b .{ abs_int, signedness };
            },
            .ComptimeInt => {
                const abs_int = if (n >= 0) n else -n;
                const signedness = if (n >= 0) .unsigned else .signed;
                break :b .{ abs_int, signedness };
            },
            .Float, .ComptimeFloat => {
                const abs_float = if (n >= 0) n else -n;
                const abs_int = @as(comptime_int, @ceil(abs_float));
                const signedness = if (n >= 0) .unsigned else .signed;
                break :b .{ abs_int, signedness };
            },
            else => unreachable,
        }
    };

    const T_n_abs = @TypeOf(n_abs);
    if (n_abs <= 1) return std.meta.Int(signedness, 1);

    switch (mode) {
        .Smallest => {
            var bits_needed: u16 = 1;
            var max_value: T_n_abs = 1;
            while (max_value < n_abs) : (bits_needed += 1) {
                max_value = max_value * 2 + 1;
            }
            return std.meta.Int(signedness, bits_needed);
        },
        .PowerOf2 => {
            var bits_needed: u16 = 1;
            var upper_value: T_n_abs = 1 << bits_needed;
            while (upper_value < n_abs) {
                bits_needed *= 2;
                upper_value = 1 << bits_needed;
            }
            return std.meta.Int(signedness, bits_needed);
        },
    }
}

test {
    // int
    try expectEqual(u1, IntFromAnyNumeric(@as(u8, 0), .Smallest));
    try expectEqual(u1, IntFromAnyNumeric(@as(u8, 1), .PowerOf2));
    try expectEqual(u6, IntFromAnyNumeric(@as(u8, 44), .Smallest));
    // float
    try expectEqual(u1, IntFromAnyNumeric(@as(f16, 1), .Smallest));
    // comptime_int
    try expectEqual(u6, IntFromAnyNumeric(@as(comptime_int, 44), .Smallest));
    try expectEqual(u8, IntFromAnyNumeric(@as(comptime_int, 44), .PowerOf2));
    // comptime_float
    try expectEqual(u6, IntFromAnyNumeric(@as(comptime_float, 44.0), .Smallest));
    try expectEqual(u8, IntFromAnyNumeric(@as(comptime_float, 44.0), .PowerOf2));
}

/// Returns the closest power of two (equal or greater than `int`).
pub fn nextPowerOf2(n: anytype) @TypeOf(n) {
    comptime assertType(@TypeOf(n), .{
        .Int,
        .Float,
        .ComptimeFloat,
        .ComptimeInt,
    }, "fn {s}.n", .{@src().fn_name});

    if (n <= 1) return 1;

    const T = @TypeOf(n);
    switch (@typeInfo(T)) {
        .Int => |info| {
            const shift = @as(std.math.Log2Int(T), @intCast(info.bits - @clz(n - 1)));
            return @as(T, 1) << shift;
        },
        .Float, .ComptimeFloat => {
            return @exp2(@ceil(@log2(n)));
        },
        .ComptimeInt => {
            const T_int = IntFromAnyNumeric(n, .PowerOf2); // * convert comptime_int to int
            return std.math.maxInt(T_int);
        },
        else => unreachable,
    }
}

test nextPowerOf2 {
    // greater
    try expectEqual(4, nextPowerOf2(@as(u8, 3)));
    try expectEqual(4, nextPowerOf2(@as(i8, 3)));
    try expectEqual(4.0, nextPowerOf2(@as(f16, 3.0)));
    //try expectEqual(4, nextPowerOf2(@as(comptime_int, 3.0)));
    try expectEqual(4.0, nextPowerOf2(@as(comptime_float, 3.0)));
    // equal
    try expectEqual(2, nextPowerOf2(@as(u8, 2)));
    try expectEqual(2, nextPowerOf2(@as(i8, 2)));
    try expectEqual(2.0, nextPowerOf2(@as(f16, 2.0)));
    //try expectEqual(2.0, nextPowerOf2(@as(comptime_int, 2.0)));
    try expectEqual(2.0, nextPowerOf2(@as(comptime_float, 2.0)));
    // edge case
    try expectEqual(1, nextPowerOf2(@as(u8, 0)));
    try expectEqual(1, nextPowerOf2(@as(i8, -1)));
    try expectEqual(1.0, nextPowerOf2(@as(f16, -1.0)));
    //try expectEqual(1.0, nextPowerOf2(@as(comptime_int, -1.0)));
    try expectEqual(1.0, nextPowerOf2(@as(comptime_float, -1.0)));
}

/// Fast `a` modulus `b`, but `b` has to be a power of two.
/// Asserts `T` to be an integer.
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// very cheap   | single int sub, single int bit-op
/// -------------------------------------------------------------------
pub inline fn fastMod(comptime T: type, a: T, b: T) T {
    comptime assertType(T, .{ .Int, .ComptimeInt }, "fn {s}.T", .{@src().fn_name});
    return a & (b - 1);
}

/// Check if `int` is some power of two.
/// Asserts `int` to be an integer.
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// very cheap   | single int comp, single int sub, single int bit-op
/// -------------------------------------------------------------------
pub inline fn isPowerOf2(int: anytype) bool {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt }, "fn {s}.int", .{@src().fn_name});
    return int != 0 and (int & (int - 1)) == 0; // * powers of 2 only has one bit set
}

test isPowerOf2 {
    try expectEqual(false, isPowerOf2(0));
    try expectEqual(true, isPowerOf2(1));
    try expectEqual(true, isPowerOf2(2));
    try expectEqual(false, isPowerOf2(3));
}

/// Retrieve 10 to the power of `exp`.
/// Interface for 'power\_of\_10\_table_...'.
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// very cheap   | direct array indexing
/// -------------------------------------------------------------------
pub inline fn indexPower10(exp: u4, comptime typ: enum { Float, Int }) if (typ == .Float) f64 else u64 {
    switch (typ) {
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

/// Multiply some percentage `percentage_float` with some number `n`.
/// Useful for calculating tresholds for (u)sizes and similar.
/// Adjust precision of `percent_float` by number of decimal places with `options.precision`.
/// Asserts that `percent_float` is within range [0.0, 1.0] (* overflow error is avoided).
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// cheap        | single float mul, single int div, few type conv
/// -------------------------------------------------------------------
pub fn mulPercent(percent_float: f64, num: usize, options: struct { precision: u4 = 2 }) usize {
    // checking `percent_float`
    if (!math.isFinite(percent_float) or percent_float < 0.0 or percent_float > 1.0) {
        panic("Invalid percentage, found '{d}'", .{percent_float});
    }

    // convert percentage to fixed-point
    const precision_p10_float: f64 = indexPower10(options.precision, .Float);
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, num) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = indexPower10(options.precision, .Int);
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
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// very cheap   | single int add, single int comp
/// -------------------------------------------------------------------
pub inline fn wrapIncrement(comptime T: type, num: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat }, "fn {s}.T", .{@src().fn_name});
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
///
///  computation |                        about
/// -------------|-----------------------------------------------------
/// very cheap   | single int compare, single int sub
/// -------------------------------------------------------------------
pub inline fn wrapDecrement(comptime T: type, value: T, min: T, max: T) T {
    comptime assertType(T, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat }, "fn {s}.T", .{@src().fn_name});
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
