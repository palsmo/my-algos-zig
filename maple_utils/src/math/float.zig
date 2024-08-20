//! Author: palsmo
//! Status: In Progress
//! About: IEEE 754 Float Numeric Functionality

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertComptime = mod_assert.misc.assertComptime;
const assertType = mod_assert.misc.assertType;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;

/// Returns the number of exponent bits for float `T`.
/// Type `T` is asserted to be a *.Float*
inline fn floatExponentBits(comptime T: type) comptime_int {
    comptime assertType(T, .{.Float});
    return switch (@bitSizeOf(T)) { // * comptime branch prune
        16 => 5,
        32 => 8,
        64 => 11,
        80 => 15,
        128 => 15,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T)},
        )),
    };
}

/// Returns the number of bits in the mantissa for float `T`.
/// Type `T` is asserted to be a *.Float*.
pub inline fn floatMantissaBits(comptime T: type) comptime_int {
    comptime assertType(T, .{.Float});
    return switch (@bitSizeOf(T)) { // * comptime branch prune
        16 => 10,
        32 => 23,
        64 => 52,
        80 => 64,
        128 => 112,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T)},
        )),
    };
}

/// Returns the number of fractional bits in the mantissa for float `T`.
/// Type `T` is asserted to be a *.Float*.
pub inline fn floatFractionalBits(comptime T: type) comptime_int {
    comptime assertType(T, .{.Float});
    // standard IEEE floats have an implicit leading bit (either 0 or 1) in the mantissa
    // f80 is special and has an explicitly stored bit in the Most Significant Bit (MSB)
    return switch (@bitSizeOf(T)) { // * comptime branch prune
        16 => 10,
        32 => 23,
        64 => 52,
        80 => 63,
        128 => 112,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T)},
        )),
    };
}

/// Returns the maximum exponent for normal float `T`.
/// Type `T` is asserted to be a *.Float*.
pub inline fn floatExponentMax(comptime T: type) comptime_int {
    comptime assertType(T, .{.Float});
    return (1 << (floatExponentBits(T) - 1)) - 1; // f16 e.g. sign: 0, exp: _111_...
}

/// Returns the minimum exponent for normal float `T`.
/// Type `T` is asserted to be a *.Float*.
pub inline fn floatExponentMin(comptime T: type) comptime_int {
    return -(1 << (floatExponentBits(T) - 1)) + 2; // f16 e.g. sign: 1, exp: _111_...
}

/// Returns the fixed bias for float `T`'s exponent.
/// Type `T` is asserted to be a *.Float*.
const floatExponentBias = floatExponentMax;

/// Construct float `T` from it's components.
/// Type `T` is asserted to be a *.Float*
/// Compute - very cheap, few bit operations.
inline fn floatConstruct(
    comptime T: type,
    exponent: std.meta.Int(.unsigned, @bitSizeOf(T)),
    mantissa: std.meta.Int(.unsigned, @bitSizeOf(T)),
    comptime mode: enum { BiasedExp, UnbiasedExp },
) T {
    comptime assertType(T, .{.Float});
    const biased_exponent = switch (mode) { // * comptime branch prune
        .BiasedExp => exponent,
        .UnbiasedExp => exponent + floatExponentBias(T),
    };
    // combine exponent and mantissa i.e. shift and OR to correct positions
    const shifted_exponent = biased_exponent << floatMantissaBits(T);
    const combined = shifted_exponent | mantissa;
    // interpret the bit pattern as a float
    return @as(T, @bitCast(combined));
}

test floatConstruct {}

/// Creates a raw "1.0" mantissa for float `T`.
/// Used to dedupe f80 logic.
/// Type `T` is asserted to be a *.Float*.
inline fn floatMantissaOne(comptime T: type) comptime_int {
    assertType(T, .{.Float});
    return if (@bitSizeOf(T) == 80) 1 << floatFractionalBits(T) else 0;
}

/// Returns the inf-value for float `T`.
/// Type `T` is asserted to be a *.Float*
/// Infinity is rep. by all 1s in the exponent field and 0s in the mantissa (except for f80).
pub inline fn floatInf(comptime T: type, comptime mode: enum { Positive, Negative }) T {
    assertType(T, .{.Float});
    switch (mode) { // * comptime branch prune
        .Positive => floatConstruct(T, floatExponentMax(T) + 1, floatMantissaOne(T), .BiasedExp),
        .Negative => floatConstruct(T, floatExponentMin(T) + 1, floatMantissaOne(T), .BiasedExp),
    }
}

/// Check if float `flt` is some infinity.
/// Type of `flt` is asserted to be *.Float*
/// Compute - very cheap, single comparison or few bit operations
pub inline fn floatIsInf(flt: anytype, comptime mode: enum { Positive, Negative, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    const T_flt = @TypeOf(flt);
    switch (mode) { // * comptime branch prune
        .Both => {
            const TBits = std.meta.Int(.unsigned, @bitSizeOf(T_flt));
            const bitmask_no_sign = ~@as(TBits, 0) >> 1;
            return @as(TBits, @bitCast(flt)) & bitmask_no_sign == @as(TBits, @bitCast(floatInf(T_flt)));
        },
        else => return flt == comptime floatInf(T_flt, mode),
    }
}

test floatIsInf {}

//test floatIsInf {
//    const flt_norm: f16 = 444.4;
//    const flt_inf: f16 = inf(f16);
//    try expectEqual(false, isInf(flt_norm, .Both));
//    try expectEqual(true, isInf(flt_inf, .Both));
//}
