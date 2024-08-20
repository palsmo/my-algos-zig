//! Author: palsmo
//! Status: In Progress
//! About: IEEE 754 Float Numeric Functionality
//!
//! Float Diagram:
//!
//!  format  | (MSB)                                   |                   about
//!          |                 |       mantissa        |
//!          |                 |  leading-bit   |      |
//! ---------|-----------------------------------------|--------------------------------------------
//! f16      | sign | exponent | [implicit 1/0] . frac | 16-bit (1, 5, 10), half precision
//!          |                                         | range: ±6.55e-5 to ±65504
//!          |                                         | precision: ~3.31 decimal digits
//!          |                                         | use: graphics, machine learning
//! ---------|-----------------------------------------|--------------------------------------------
//! f32      | sign | exponent | [implicit 1/0] . frac | 32-bit (1, 8, 23), single precision
//!          |                                         | range: ±1.18e-38 to ±3.4e38
//!          |                                         | precision: ~7.22 decimal digits
//!          |                                         | use: graphics, audio, general purpose
//! ---------|-----------------------------------------|--------------------------------------------
//! f64      | sign | exponent | [implicit 1/0] . frac | 64-bit (1, 11, 52), double precision
//!          |                                         | range: ±2.23e-308 to ±1.80e308
//!          |                                         | precision: ~15.95 decimal digits
//!          |                                         | use: scientific, financial computations
//! ---------|-----------------------------------------|--------------------------------------------
//! f80      | sign | exponent | [explicit 1/0] . frac | 80-bit (1, 15, 1+63), extended precision
//!          |                                         | range: ±3.37e-4932 to ±1.18e4932
//!          |                                         | precision: ~19.27 decimal digits
//!          |                                         | use: legacy, intermediate calc, x87 FPU
//! ---------|-----------------------------------------|--------------------------------------------
//! f128     | sign | exponent | [implicit 1/0] . frac | 128-bit (1, 15, 112), quadruple precision
//!          |                                         | range: ±3.36e-4932 to ±1.19e4932
//!          |                                         | precision: ~34.02 decimal digits
//!          |                                         | use: high-precision scientific simulations
//! ------------------------------------------------------------------------------------------------

const std = @import("std");

const proj_shared = @import("./../../../shared.zig");
const mod_assert = @import("../assert/root.zig");
const mod_typ = @import("../typ/root.zig");

const ExecMode = proj_shared.ExecMode;
const T_int = mod_typ.misc.T_int;
const assertComptime = mod_assert.misc.assertComptime;
const assertType = mod_assert.misc.assertType;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Returns the number of exponent bits for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn exponentBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return switch (T_flt) { // * comptime branch prune
        f16 => 5,
        f32 => 8,
        f64 => 11,
        f80 => 15,
        f128 => 15,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T_flt)},
        )),
    };
}

/// Returns the number of bits in the mantissa for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn mantissaBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return switch (T_flt) { // * comptime branch prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 64,
        f128 => 112,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T_flt)},
        )),
    };
}

/// Returns the number of fractional bits in the mantissa for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn fractionalBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    // standard IEEE floats have an implicit leading bit (either 0 or 1) in the mantissa
    // f80 is special and has an explicitly stored bit in the most significant mantissa bit.
    return switch (T_flt) { // * comptime branch prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 63,
        f128 => 112,
        else => @compileError(comptimePrint(
            "Unsupported float, not within the IEEE float standard: '{s}'",
            .{@typeName(T_flt)},
        )),
    };
}

/// Returns the maximum exponent for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn exponentMax(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return (1 << (exponentBitsN(T_flt) - 1)) - 1;
}

test exponentMax {
    try expectEqual(15, exponentMax(f16));
    try expectEqual(127, exponentMax(f32));
    try expectEqual(1023, exponentMax(f64));
    try expectEqual(16383, exponentMax(f80));
    try expectEqual(16383, exponentMax(f128));
}

/// Returns the minimum exponent for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn exponentMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return -(1 << (exponentBitsN(T_flt) - 1)) + 2;
}

test exponentMin {
    try expectEqual(-14, exponentMin(f16));
    try expectEqual(-126, exponentMin(f32));
    try expectEqual(-1022, exponentMin(f64));
    try expectEqual(-16382, exponentMin(f80));
    try expectEqual(-16382, exponentMin(f128));
}

/// Returns the maximum mantissa for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn mantissaMax(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return (1 << (mantissaBitsN(T_flt) - 1)) - 1;
}

test mantissaMax {
    try expectEqual(0x3FF, mantissaMax(f16));
    try expectEqual(0x7FFFFF, mantissaMax(f32));
    try expectEqual(0xFFFFFFFFFFFFF, mantissaMax(f64));
    try expectEqual(0x7FFFFFFFFFFFFFFF, mantissaMax(f80));
    try expectEqual(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, mantissaMax(f128));
}

/// Returns the minimum mantissa for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn mantissaMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return -(1 << (mantissaBitsN(T_flt) - 1)) + 2;
}

test mantissaMin {
    try expectEqual(-0x3FE, mantissaMin(f16));
    try expectEqual(-0x7FFFFE, mantissaMin(f32));
    try expectEqual(-0xFFFFFFFFFFFFE, mantissaMin(f64));
    try expectEqual(-0x7FFFFFFFFFFFFFFE, mantissaMin(f80));
    try expectEqual(-0xFFFFFFFFFFFFFFFFFFFFFFFFFFFE, mantissaMin(f128));
}

/// Returns the *fixed bias* for `T_flt`'s exponent.
/// Used when converting an unbiased exponent to biased.
/// Type `T_flt` is asserted to be a *float*.
pub const exponentBias = exponentMax;

/// Convert an `unbias_exp` to the biased version.
/// Type of `unbias_exp` is asserted to be an *.Int*
pub inline fn exponentBiasFromUnbias(unbias_exp: anytype) @TypeOf(unbias_exp) {
    comptime assertType(@TypeOf(unbias_exp), .{.Int});
    return unbias_exp +% exponentBias();
}

/// Construct `T_flt` from its *components*.
/// Bit-pattern: [ sign-bit | exponent | 'leading-bit' . fractional ]
/// Expects a *biased* `expo`, `lead` is only accounted for when `T_flt` is *f80*.
/// Type `T_flt` is asserted to be a *float*.
/// Compute - *very cheap*, few bitwise operations.
/// Issue key specs:
/// - Panic when any *component* would overflow in `T_flt` (only *.Safe* `exec_mode`).
pub inline fn construct(
    comptime T_flt: type,
    sign: T_int(.unsigned, @bitSizeOf(T_flt)),
    expo: T_int(.unsigned, @bitSizeOf(T_flt)),
    lead: T_int(.unsigned, @bitSizeOf(T_flt)),
    frac: T_int(.unsigned, @bitSizeOf(T_flt)),
    comptime exec_mode: ExecMode,
) T_flt {
    comptime assertType(T_flt, .{.Float});

    switch (exec_mode) { // * comptime branch prune
        .Uncheck => {},
        .Safe => {
            if (sign > 1) panic("The sign '{d}' overflows single bit.", .{sign});
            if (expo > exponentMax(T_flt)) panic("The exponent '{d}' doesn't fit within {d} bits.", .{ expo, exponentBitsN(T_flt) });
            if (lead > 1) panic("The leading-bit '{d}' overflows single bit.", .{lead});
            if (frac > mantissaMax(T_flt)) panic("The fractional '{d}' doesn't fit within {d} bits.", .{ frac, fractionalBitsN(T_flt) });
        },
    }

    const sign_shift = @bitSizeOf(T_flt) - 1;
    const expo_shift = mantissaBitsN(T_flt);

    switch (T_flt) { // * comptime branch prune
        f80 => {
            const lead_shift = fractionalBitsN(T_flt);
            const pattern = (sign << sign_shift) | (expo << expo_shift) | (lead << lead_shift) | frac;
            return @bitCast(pattern);
        },
        else => {
            const pattern = (sign << sign_shift) | (expo << expo_shift) | frac;
            return @bitCast(pattern);
        },
    }
}

test construct {}

/// Returns the inf-value for `T_flt`.
/// Type `T_flt` is asserted to be a *float*.
/// Infinity is rep. by all 1s in the exponent field and 0s in the mantissa (except for f80).
pub inline fn inf(comptime T_flt: type, comptime mode: enum { Positive, Negative }) T_flt {
    assertType(T_flt, .{.Float});
    switch (mode) { // * comptime branch prune
        .Positive => comptime construct(T_flt, 0, exponentMax(T_flt), 0, 0),
        .Negative => comptime construct(T_flt, 1, exponentMin(T_flt), 0, 0),
    }
}

/// Check if `flt` is some infinity.
/// Type of `flt` is asserted to be *float*.
/// Compute - very cheap, single comparison or few bitwise operations.
pub inline fn isInf(flt: anytype, comptime mode: enum { Positive, Negative, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});

    const T_flt = @TypeOf(flt);

    switch (mode) { // * comptime branch prune
        .Both => {
            const T_bit_oper = T_int(.unsigned, @bitSizeOf(T_flt));
            const bitmask_no_sign = ~@as(T_int, 0) >> 1;
            const bit_operable_flt: T_bit_oper = @bitCast(flt);
            const bit_operable_inf: T_bit_oper = comptime @bitSizeOf(inf(T_flt, .Positive));
            return ((bit_operable_flt & bitmask_no_sign) == bit_operable_inf);
        },
        else => {
            return (flt == comptime inf(T_flt, mode));
        },
    }
}

test isInf {}

/// Returns the canonical NaN for `T_flt`.
/// `mode` *.Quiet* (qNaN), most common, doesn't raise exception when used.
/// `mode` *.Signaling* (sNaN), raises an exception when used in operations.
/// Type `T_flt` is asserted to be a *float*.
pub inline fn nan(comptime T_flt: type, comptime mode: enum { Quiet, Signaling }) T_flt {
    comptime assertType(T_flt, .{.Float});
    return switch (mode) { // * comptime branch prune
        .Quiet => comptime construct(T_flt, 0, exponentMax(T_flt), 0, (1 << (fractionalBitsN(T_flt) - 1)), .Uncheck),
        .Signaling => comptime construct(T_flt, 0, exponentMax(T_flt), 0, (1 << (fractionalBitsN(T_flt) - 2)), .Uncheck),
    };
}

/// Check if `flt` is some NaN.
/// Type of `flt` is asserted to be a *float*.
/// Compute - *very cheap*, single comparison or few bitwise operations.
pub inline fn isNan(flt: anytype, comptime mode: enum { Quiet, Signaling, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});

    const T_flt = @TypeOf(flt);
    const is_nan = (flt != flt);

    switch (mode) { // * comptime branch prune
        .Both => return is_nan,
        .Quiet => {
            const T_bit_oper = T_int(.unsigned, @bitSizeOf(T_flt));
            const bitmask_quiet = 1 << fractionalBitsN(T_flt);
            const bit_operable_flt: T_bit_oper = @bitCast(flt);
            return (is_nan and ((bit_operable_flt & bitmask_quiet) != 0));
        },
        .Signaling => {
            const T_bit_oper = T_int(.unsigned, @bitSizeOf(T_flt));
            const bitmask_signal = 1 << fractionalBitsN(T_flt);
            const bit_operable_flt: T_bit_oper = @bitCast(flt);
            return (is_nan and ((bit_operable_flt & bitmask_signal) == 0));
        },
    }
}

//test floatIsInf {
//    const flt_norm: f16 = 444.4;
//    const flt_inf: f16 = inf(f16);
//    try expectEqual(false, isInf(flt_norm, .Both));
//    try expectEqual(true, isInf(flt_inf, .Both));
//}
