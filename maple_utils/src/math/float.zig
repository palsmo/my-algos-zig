//! Author: palsmo
//! Status: In Progress
//! About: IEEE 754 Float Numeric Functionality
//!
//! Float Diagram:
//!
//!  format  | (MSB)           |       mantissa        |                   about
//!          |                 |  leading-bit   |      |
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f16      | sign | exponent | [implicit 1/0] . frac | 16-bit (1, 5, 10), half precision
//!          |                                         | range: ±6.55e-5 to ±65504
//!          |                                         | precision: ~3.31 decimal digits
//!          |                                         | use: graphics, machine learning
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f32      | sign | exponent | [implicit 1/0] . frac | 32-bit (1, 8, 23), single precision
//!          |                                         | range: ±1.18e-38 to ±3.4e38
//!          |                                         | precision: ~7.22 decimal digits
//!          |                                         | use: graphics, audio, general purpose
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f64      | sign | exponent | [implicit 1/0] . frac | 64-bit (1, 11, 52), double precision
//!          |                                         | range: ±2.23e-308 to ±1.80e308
//!          |                                         | precision: ~15.95 decimal digits
//!          |                                         | use: scientific, financial computations
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f80      | sign | exponent | [explicit 1/0] . frac | 80-bit (1, 15, 1+63), extended precision
//!          |                                         | range: ±3.37e-4932 to ±1.18e4932
//!          |                                         | precision: ~19.27 decimal digits
//!          |                                         | use: legacy, intermediate calc, x87 FPU
//! ---------|------+----------+----------------+------|--------------------------------------------
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
const T_float = mod_typ.misc.T_float;
const T_int = mod_typ.misc.T_int;
const assertType = mod_assert.misc.assertType;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Returns the number of exponent bits for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn exponentBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return switch (T_flt) { // * comptime branch prune
        f16 => 5,
        f32 => 8,
        f64 => 11,
        f80 => 15,
        f128 => 15,
        else => unreachable,
    };
}

/// Returns the number of bits in the mantissa for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn mantissaBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return switch (T_flt) { // * comptime branch prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 64,
        f128 => 112,
        else => unreachable,
    };
}

/// Returns the number of fractional bits in the mantissa for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn fractionBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    // standard IEEE floats have an implicit leading bit (either 0 or 1) in the mantissa
    // f80 is special and has an explicitly stored bit in the most significant mantissa bit.
    return switch (T_flt) { // * comptime branch prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 63,
        f128 => 112,
        else => unreachable,
    };
}

/// Returns the biggest normal value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, comptime-defined constant.
pub inline fn max(comptime T_flt: type) comptime_int {
    assertType(T_flt, .{.Float});
    return comptime construct(T_flt, 0, exponentMax(T_flt, .Normal), 0, fractionMax(T_flt));
}

/// Returns the smallest normal/subnormal value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, comptime-defined constant.
pub inline fn min(comptime T_flt: type, comptime mode: enum { Normal, Subnormal }) comptime_int {
    assertType(T_flt, .{.Float});
    return switch (mode) { // * comptime branch prune
        .Normal => comptime construct(T_flt, 1, exponentMax(T_flt, .Normal), 0, 0),
        .Subnormal => comptime construct(T_flt, 0, exponentMin(T_flt, .Special), 0, 1),
    };
}

/// Returns the maximum exponent for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentMax(comptime T_flt: type, comptime mode: enum { Normal, Special }) comptime_int {
    assertType(T_flt, .{.Float});
    return switch (mode) { // * comptime branch prune
        .Special => (1 << exponentBitsN(T_flt)) - 1,
        .Normal => (1 << (exponentBitsN(T_flt) - 1)) - 1,
    };
}

test exponentMax {
    try expectEqual(15, exponentMax(f16, .Normal));
    try expectEqual(127, exponentMax(f32, .Normal));
    try expectEqual(1023, exponentMax(f64, .Normal));
    try expectEqual(16383, exponentMax(f80, .Normal));
    try expectEqual(16383, exponentMax(f128, .Normal));
}

/// Returns the minimum exponent for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentMin(comptime T_flt: type, comptime mode: enum { Normal, Special }) comptime_int {
    assertType(T_flt, .{.Float});
    return switch (mode) { // * comptime branch prune
        .Special => 0,
        .Normal => 1,
    };
}

test exponentMin {
    try expectEqual(-14, exponentMin(f16));
    try expectEqual(-126, exponentMin(f32));
    try expectEqual(-1022, exponentMin(f64));
    try expectEqual(-16382, exponentMin(f80));
    try expectEqual(-16382, exponentMin(f128));
}

/// Returns the maximum fractional for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn fractionMax(comptime T_flt: type) comptime_int {
    assertType(T_flt, .{.Float});
    return (1 << (fractionBitsN(T_flt) - 1)) - 1;
}

/// Returns the minimum fractional for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn fractionMin(comptime T_flt: type) comptime_int {
    assertType(T_flt, .{.Float});
    return -fractionMax(T_flt) + 1;
}

/// Returns the maximum mantissa for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
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
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn mantissaMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return -mantissaMax(T_flt) + 1;
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
/// Compute - *very cheap*, few basic operations.
/// Asserts `T_flt` to be a *float* type.
pub const exponentBias = exponentMax;

/// Convert an `unbias_exp` to the biased version.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, single addition / few comparisons.
/// Issue key specs:
/// - Panic when resulting exponent would overflow (only *.Safe* `exec_mode`).
pub inline fn exponentBiasFromUnbias(comptime T_flt: type, unbias_exp: i16, comptime exec_mode: ExecMode) u16 {
    comptime assertType(T_flt, .{.Float});
    switch (exec_mode) { // * comptime branch prune
        .Uncheck => {
            return @intCast(unbias_exp +% comptime exponentBias(T_flt));
        },
        .Safe => {
            const bits_exp_n = exponentBitsN(T_flt);
            const unbias_exp_max = comptime std.math.maxInt(T_int(.signed, bits_exp_n));
            const unbias_exp_min = comptime std.math.minInt(T_int(.signed, bits_exp_n));
            if (unbias_exp > unbias_exp_max or unbias_exp < unbias_exp_min) {
                panic(
                    "Can't convert to biased form, `unbias_exp` value '{d}' has to fit within {d} bits.",
                    .{ unbias_exp, bits_exp_n },
                );
            }
            return @intCast(unbias_exp +% comptime exponentBias(T_flt));
        },
    }
}

/// Convert a `bias_exp` to the unbiased version.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, single subtraction / few comparisons.
/// Issue key specs:
/// - Panic when resulting exponent would overflow (only *.Safe* `exec_mode`).
pub inline fn exponentUnbiasFromBias(comptime T_flt: type, bias_exp: u16, comptime exec_mode: ExecMode) i16 {
    comptime assertType(T_flt, .{.Float});
    switch (exec_mode) { // * comptime branch prune
        .Uncheck => {
            return @intCast(bias_exp -% comptime exponentBias(T_flt));
        },
        .Safe => {
            const bits_exp_n = exponentBitsN(T_flt);
            const bias_exp_max = comptime std.math.maxInt(T_int(.unsigned, bits_exp_n));
            const bias_exp_min = comptime std.math.minInt(T_int(.unsigned, bits_exp_n));
            if (bias_exp > bias_exp_max or bias_exp < bias_exp_min) {
                panic(
                    "Can't convert to unbiased form, `bias_exp` value '{d}' has to fit within {d} bits.",
                    .{ bias_exp, bits_exp_n },
                );
            }
            return @intCast(bias_exp -% comptime exponentBias(T_flt));
        },
    }
}

/// Constructs `T_flt` from its *components*.
/// Bit-pattern: [ sign-bit | exponent | 'leading-bit' . fraction ]
/// Assumes *biased* `expo`, the `lead` only for *f80*.
/// Assumes `T_flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations.
pub inline fn construct(
    comptime T_flt: type,
    sign: u1,
    expo: u15,
    lead: u1,
    frac: T_int(.unsigned, fractionBitsN(T_float(@bitSizeOf(T_flt)))),
) T_flt {
    const sign_shift = @typeInfo(T_flt).Float.bits - 1;
    const expo_shift = mantissaBitsN(T_flt);
    switch (T_flt) { // * comptime branch prune
        f80 => {
            const lead_shift = fractionBitsN(T_flt);
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

/// Check if `flt` is *normal*, *subnormal* or *zero*.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations.
pub inline fn isFinite(flt: anytype) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    const T_flt = @TypeOf(flt);
    const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
    const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
    const inf_bit_oper: T_flt_bit_oper = comptime @bitCast(inf(T_flt, .Positive));
    const bitmask_no_sign = ~@as(T_flt_bit_oper, 0) >> 1;
    return ((flt_bit_oper & bitmask_no_sign) < inf_bit_oper);
}

test isFinite {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // normals
        try expectEqual(true, isFinite(@as(T, 4.0)));
        try expectEqual(true, isFinite(@as(T, -4.0)));
        // subnormal and zero
        try expectEqual(true, isFinite(@as(T, std.math.floatTrueMin)));
        //try expect(isFinite(@as(T, 0.0)));
        //try expect(isFinite(@as(T, -0.0)));
        //try expect(isFinite(math.floatTrueMin(T)));
        //// other float limits
        //try expect(isFinite(math.floatMin(T)));
        //try expect(isFinite(math.floatMax(T)));
        //// inf & nan
        //try expect(!isFinite(math.inf(T)));
        //try expect(!isFinite(-math.inf(T)));
        //try expect(!isFinite(math.nan(T)));
        //try expect(!isFinite(-math.nan(T)));
    }
}

/// Check if `flt` is neither *zero*, *subnormal*, *infinity* or *NaN*.
/// Assert `T_flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations.
pub inline fn isNormal(flt: anytype) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    const T_flt = @TypeOf(flt);
    const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
    const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
    const bitmask_no_sign = ~@as(T_flt_bit_oper, 0) >> 1;
    const exp_incrementer = 1 << mantissaBitsN(T_flt);
    // Add 1 to the exponent, if it overflows to 0 or becomes 1,
    // then it was all zeroes (zero/subnormal) or all ones (inf/nan).
    // The sign bit is removed because all ones would overflow into it.
    // For f80, even though it has an explicit leading-bit stored,
    // the exponent takes priority due to its higher significance.
    return ((bitmask_no_sign & (flt_bit_oper +% exp_incrementer)) >= (exp_incrementer << 1));
}

pub inline fn isNormalOrZero(flt: anytype) bool {
    return (flt == 0) or isNormal(flt);
}

pub inline fn isZero(flt: anytype, comptime mode: enum { Positive, Negative, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    switch (mode) { // * comptime branch prune
        .Both => flt == 0,
        .Positive => {
            const T_flt = @TypeOf(flt);
            const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
            const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
            const pos_zero_bit_oper: T_flt_bit_oper = 0;
            return (flt_bit_oper == pos_zero_bit_oper);
        },
        .Negative => {
            const T_flt = @TypeOf(flt);
            const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
            const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
            const neg_zero_bit_oper: T_flt_bit_oper = 1 << (@typeInfo(T_flt).Float.bits - 1);
            return (flt_bit_oper == neg_zero_bit_oper);
        },
    }
}

/// Returns the inf-value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn inf(comptime T_flt: type, comptime mode: enum { Positive, Negative }) comptime_int {
    assertType(T_flt, .{.Float});
    switch (mode) { // * comptime branch prune
        .Positive => comptime construct(T_flt, 0, exponentMax(T_flt) + 1, 0, 0),
        .Negative => comptime construct(T_flt, 1, exponentMin(T_flt) + 1, 0, 0),
    }
}

/// Check if `flt` is some infinity.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, single comparison / few bitwise operations.
pub inline fn isInf(flt: anytype, comptime mode: enum { Positive, Negative, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    const T_flt = @TypeOf(flt);
    switch (mode) { // * comptime branch prune
        .Both => {
            const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
            const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
            const inf_bit_oper: T_flt_bit_oper = comptime inf(T_flt, .Positive);
            const bitmask_no_sign = ~@as(T_int, 0) >> 1;
            return ((flt_bit_oper & bitmask_no_sign) == inf_bit_oper);
        },
        .Positive, .Negative => {
            return (flt == comptime inf(T_flt, mode));
        },
    }
}

test isInf {
    //    const flt_norm: f16 = 444.4;
    //    const flt_inf: f16 = inf(f16);
    //    try expectEqual(false, isInf(flt_norm, .Both));
    //    try expectEqual(true, isInf(flt_inf, .Both));
}

/// Returns the canonical NaN for `T_flt`.
/// `mode` *.Quiet* (qNaN), most common, doesn't raise exception when used.
/// `mode` *.Signaling* (sNaN), raises an exception when used in operations.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn nan(comptime T_flt: type, comptime mode: enum { Quiet, Signaling }) comptime_int {
    comptime assertType(T_flt, .{.Float});
    return switch (mode) { // * comptime branch prune
        .Quiet,
        => comptime construct(T_flt, 0, exponentMax(T_flt) + 1, 0, (1 << (fractionBitsN(T_flt) - 1)), .Uncheck),
        .Signaling,
        => comptime construct(T_flt, 0, exponentMax(T_flt) + 1, 0, (1 << (fractionBitsN(T_flt) - 2)), .Uncheck),
    };
}

/// Check if `flt` is some NaN.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, single comparison / few bitwise operations.
pub inline fn isNan(flt: anytype, comptime mode: enum { Quiet, Signaling, Both }) bool {
    comptime assertType(@TypeOf(flt), .{.Float});
    const T_flt = @TypeOf(flt);
    const is_nan = (flt != flt);
    switch (mode) { // * comptime branch prune
        .Both => return is_nan,
        .Quiet => {
            const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
            const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
            const bitmask_quiet = 1 << fractionBitsN(T_flt);
            return (is_nan and ((flt_bit_oper & bitmask_quiet) != 0));
        },
        .Signaling => {
            const T_flt_bit_oper = T_int(.unsigned, @typeInfo(T_flt).Float.bits);
            const flt_bit_oper: T_flt_bit_oper = @bitCast(flt);
            const bitmask_signal = 1 << fractionBitsN(T_flt);
            return (is_nan and ((flt_bit_oper & bitmask_signal) == 0));
        },
    }
}
