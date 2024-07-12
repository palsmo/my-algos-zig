const std = @import("std");
const math = std.math;

const root = @import("./math.zig");

const Error = root.Error;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Retrieve 10 to the power of `exp`.
/// Interface for 'power\_of\_10\_table_...'.
pub inline fn pow10(exp: u4, comptime typ: enum { float, int }) if (typ == .float) f64 else u64 {
    switch (typ) {
        .float => return power_of_10_table_float[exp],
        .int => return power_of_10_table_int[exp],
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
/// Asserts that `percent_float` is within range [0.0, 1.0].
/// Adjust precision of `percent_float` by setting number of decimal places with `options.precision`.
pub fn mulPercent(percent_float: f64, n: usize, options: struct { precision: u4 = 2 }) usize {
    // checking `percent_float`
    if (!math.isFinite(percent_float) or percent_float < 0 or percent_float > 1.0) {
        panic("Invalid percentage, found '{d}'", .{percent_float});
    }

    // convert percentage to fixed-point
    const precision_p10_float: f64 = pow10(options.precision, .float);
    const percent_fixed: u64 = @intFromFloat(percent_float * precision_p10_float);

    const result_full: u128 = @as(u128, n) * @as(u128, percent_fixed);

    // * effectively rounds up when `result_full` frac-part >= "0.5", down otherwise
    const precision_p10_int: u64 = pow10(options.precision, .int);
    const result_round: u128 = result_full + (precision_p10_int >> 1); // i.e. precision_p10_int / 2
    const result: u128 = result_round / precision_p10_int;

    return @intCast(result);
}

test mulPercent {
    { // test functionality
        try expectEqual(@as(usize, 3), mulPercent(0.3, 10, .{}));
        try expectEqual(@as(usize, 0), mulPercent(0.0, 10, .{}));
        try expectEqual(@as(usize, 0), mulPercent(0.5, 0, .{}));
        try expectEqual(@as(usize, 10), mulPercent(1.0, 10, .{}));
    }
    { // test rounding
        try expectEqual(@as(usize, 3), mulPercent(0.33, 10, .{}));
        try expectEqual(@as(usize, 7), mulPercent(0.66, 10, .{}));
    }
    { // test precision
        try expectEqual(@as(usize, 0), mulPercent(0.9, 100, .{ .precision = 0 }));
        try expectEqual(@as(usize, 100), mulPercent(1.0, 100, .{ .precision = 0 }));
        try expectEqual(@as(usize, 4_567), mulPercent(0.4567, 10_000, .{ .precision = 4 }));
    }
    { // test large `n`
        const max_usize = math.maxInt(usize);
        try expectEqual(max_usize, mulPercent(1.0, max_usize, .{}));
        try expectEqual((max_usize + 1) / 2, mulPercent(0.5, max_usize, .{}));
    }
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
