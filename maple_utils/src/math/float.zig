//! Author: palsmo
//! Status: In Progress
//! About: IEEE Float Numeric Functionality

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertComptime = mod_assert.misc.assertComptime;
const assertType = mod_assert.misc.assertType;
const expectEqual = std.testing.expectEqual;

///// Returns the number of exponent bits for float type `T`.
///// Assumes `T` to be float type.
//inline fn floatExponentBits(comptime T: type) comptime_int {
//    return switch (@typeInfo(T).Float.bits) {
//        16 => 5,
//        32 => 8,
//        64 => 11,
//        80 => 15,
//        128 => 15,
//        else => unreachable,
//    };
//}
//
///// Returns the maximum exponent for normal float type `T`.
//inline fn floatExponentMax(comptime T: type) comptime_int {
//    return (1 << (floatExponentBits(T) - 1)) - 1;
//}
//
///// Creates floating point
//inline fn floatConstruct(
//    comptime T: type,
//    comptime exponent: comptime_int,
//    comptime mantissa: comptime_int,
//) T {
//    const TBits = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @bitSizeOf(T) } });
//    const biased_exponent = @as(TBits, exponent + floatExponentMax(T));
//    return @as(T, @bitCast((biased_exponent << floatMantissaBits(T)) | @as(TBits, mantissa)));
//}

/// Returns the inf-value for type `T`.
/// Asserts `T` to be a float type.
pub inline fn inf(comptime T: type) T {
    assertComptime(@src().fn_name);
    assertType(T, .{.Float});
    return std.math.inf(T);
}

/// Returns whether `flt` is positive infinity.
/// Asserts `flt` to be a float.
pub inline fn isInf(flt: anytype, comptime mode: enum { Positive, Negative, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});

    const T_flt = @TypeOf(flt);

    switch (mode) { // * comptime branch prune
        .Positive => return flt == comptime std.math.inf(T_flt),
        .Negative => return flt == comptime -std.math.inf(T_flt),
        .Both => return std.math.isInf(flt),
    }
}

test isInf {
    const flt_norm: f16 = 444.4;
    const flt_inf: f16 = inf(f16);
    try expectEqual(false, isInf(flt_norm, .Both));
    try expectEqual(true, isInf(flt_inf, .Both));
}
