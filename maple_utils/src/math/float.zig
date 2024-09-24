//! Author: palsmo
//! Status: In Progress
//! Brief: IEEE 754 Float Numeric Functionality
//!
//! Float Diagram:
//!
//!  format  | (MSB)           |       mantissa        |                   about
//!          |                 |  leading-bit   |      |
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f16      | sign | exponent | [implicit 1/0] . frac | 16-bit (1, 5, 10), half precision
//!          |                                         | precision: ~3.31 decimal digits
//!          |                                         | use: graphics, machine learning
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f32      | sign | exponent | [implicit 1/0] . frac | 32-bit (1, 8, 23), single precision
//!          |                                         | precision: ~7.22 decimal digits
//!          |                                         | use: graphics, audio, general purpose
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f64      | sign | exponent | [implicit 1/0] . frac | 64-bit (1, 11, 52), double precision
//!          |                                         | precision: ~15.95 decimal digits
//!          |                                         | use: scientific, financial computations
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f80      | sign | exponent | [explicit 1/0] . frac | 80-bit (1, 15, 1+63), extended precision
//!          |                                         | precision: ~19.27 decimal digits
//!          |                                         | use: legacy, intermediate calc, x87 FPU
//! ---------|------+----------+----------------+------|--------------------------------------------
//! f128     | sign | exponent | [implicit 1/0] . frac | 128-bit (1, 15, 112), quadruple precision
//!          |                                         | precision: ~34.02 decimal digits
//!          |                                         | use: high-precision scientific simulations
//! ------------------------------------------------------------------------------------------------

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_type = @import("../type/root.zig");

const ExecMode = prj.modes.ExecMode;
const TFloat = mod_type.misc.TFloat;
const TInt = mod_type.misc.TInt;
const ValueError = prj.errors.ValueError;
const assertType = mod_assert.assertType;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const panic = std.debug.panic;

/// Returns the number of bits in the *exponent* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn exponentBitsN(comptime T_flt: type) comptime_int {
    assertType(T_flt, .{.float});
    return switch (T_flt) { // * comptime prune
        f16 => 5,
        f32 => 8,
        f64 => 11,
        f80 => 15,
        f128 => 15,
        else => unreachable,
    };
}

/// Returns the number of bits in the *mantissa* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn mantissaBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return switch (T_flt) { // * comptime prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 64,
        f128 => 112,
        else => unreachable,
    };
}

/// Returns the number of *fractional bits* in the *mantissa* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn fractionBitsN(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    // standard IEEE floats have an implicit leading bit (either 0 or 1) in the mantissa
    // f80 is special and has an explicitly stored bit in the most significant mantissa bit.
    return switch (T_flt) { // * comptime prune
        f16 => 10,
        f32 => 23,
        f64 => 52,
        f80 => 63,
        f128 => 112,
        else => unreachable,
    };
}

/// Returns the maximum biased *exponent* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentBiasedMax(comptime T_flt: type, comptime mode: enum { normal, special }) comptime_int {
    comptime assertType(T_flt, .{.float});
    return switch (mode) { // * comptime prune
        .normal => (1 << exponentBitsN(T_flt)) - 2,
        .special => (1 << exponentBitsN(T_flt)) - 1,
    };
}

test exponentBiasedMax {
    try expectEqual(0x1E, exponentBiasedMax(f16, .normal));
    try expectEqual(0x1F, exponentBiasedMax(f16, .special));
    try expectEqual(0xFE, exponentBiasedMax(f32, .normal));
    try expectEqual(0xFF, exponentBiasedMax(f32, .special));
    try expectEqual(0x7FE, exponentBiasedMax(f64, .normal));
    try expectEqual(0x7FF, exponentBiasedMax(f64, .special));
    try expectEqual(0x7FFE, exponentBiasedMax(f80, .normal));
    try expectEqual(0x7FFF, exponentBiasedMax(f80, .special));
    try expectEqual(0x7FFE, exponentBiasedMax(f128, .normal));
    try expectEqual(0x7FFF, exponentBiasedMax(f128, .special));
}

/// Returns the minimum biased *exponent* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentBiasedMin(comptime T_flt: type, comptime mode: enum { normal, special }) comptime_int {
    comptime assertType(T_flt, .{.float});
    return switch (mode) { // * comptime prune
        .normal => 1,
        .special => 0,
    };
}

/// Returns the maximum unbiased *exponent* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentUnbiasedMax(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return (1 << exponentBitsN(T_flt) - 1) - 1;
}

test exponentUnbiasedMax {
    try expectEqual(0x0F, exponentUnbiasedMax(f16));
    try expectEqual(0x7F, exponentUnbiasedMax(f32));
    try expectEqual(0x3FF, exponentUnbiasedMax(f64));
    try expectEqual(0x3FFF, exponentUnbiasedMax(f80));
    try expectEqual(0x3FFF, exponentUnbiasedMax(f128));
}

/// Returns the minimum unbiased *exponent* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn exponentUnbiasedMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return -1 * (exponentUnbiasedMax(T_flt) - 1);
}

test exponentUnbiasedMin {
    try expectEqual(-0x0E, exponentUnbiasedMin(f16));
    try expectEqual(-0x7E, exponentUnbiasedMin(f32));
    try expectEqual(-0x3FE, exponentUnbiasedMin(f64));
    try expectEqual(-0x3FFE, exponentUnbiasedMin(f80));
    try expectEqual(-0x3FFE, exponentUnbiasedMin(f128));
}

/// Returns the maximum *fractional* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn fractionMax(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return (1 << fractionBitsN(T_flt)) - 1;
}

test fractionMax {
    try expectEqual(0x3FF, fractionMax(f16));
    try expectEqual(0x7FFFFF, fractionMax(f32));
    try expectEqual(0xFFFFFFFFFFFFF, fractionMax(f64));
    try expectEqual(0x7FFFFFFFFFFFFFFF, fractionMax(f80));
    try expectEqual(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, fractionMax(f128));
}

/// Returns the minimum *fractional* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn fractionMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return 0;
}

/// Returns the quiet nan *fractional* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn fractionNanQuiet(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return 1 << fractionBitsN(T_flt) - 1;
}

/// Returns the signaling nan *fractional* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn fractionNanSignaling(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return 1 << fractionBitsN(T_flt) - 2;
}

/// Returns the maximum *mantissa* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, few basic operations.
pub inline fn mantissaMax(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return (1 << mantissaBitsN(T_flt)) - 1;
}

test mantissaMax {
    try expectEqual(0x3FF, mantissaMax(f16));
    try expectEqual(0x7FFFFF, mantissaMax(f32));
    try expectEqual(0xFFFFFFFFFFFFF, mantissaMax(f64));
    try expectEqual(0xFFFFFFFFFFFFFFFF, mantissaMax(f80));
    try expectEqual(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF, mantissaMax(f128));
}

/// Returns the minimum *mantissa* for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn mantissaMin(comptime T_flt: type) comptime_int {
    comptime assertType(T_flt, .{.float});
    return 0;
}

/// Returns the *fixed bias* for `T_flt`'s exponent.
/// Used when converting an unbiased exponent to biased.
/// Compute - *very cheap*, few basic operations.
/// Asserts `T_flt` to be a *float* type.
pub const exponentBias = exponentUnbiasedMax;

/// Convert an `unbias_exp` to the biased version.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, single addition / few comparisons.
/// ExecMode:
/// - safe    | can throw error.
/// - uncheck | undefined when `unbias_exp` is outside bound for `T_flt`.
/// Issue key specs:
/// - Throws *OutsideBound* when `unbias_exp` is not within bound for `T_flt`.
pub inline fn exponentBiasFromUnbias(comptime T_flt: type, unbias_exp: i16, comptime exec_mode: ExecMode) switch (exec_mode) {
    .uncheck => u16,
    .safe => ValueError!u16,
} {
    comptime assertType(T_flt, .{.float});

    switch (exec_mode) { // * comptime prune
        .uncheck => {
            @setRuntimeSafety(false);
            return @bitCast(unbias_exp + exponentBias(T_flt));
        },
        .safe => {
            const unbias_exp_max = exponentUnbiasedMax(T_flt);
            const unbias_exp_min = exponentUnbiasedMin(T_flt);
            if (unbias_exp > unbias_exp_max or unbias_exp < unbias_exp_min) {
                return error.OutsideBound;
            }
            return @bitCast(unbias_exp + exponentBias(T_flt));
        },
    }
}

test exponentBiasFromUnbias {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // ok
        try expectEqual(exponentBiasedMax(T, .normal), exponentBiasFromUnbias(T, exponentUnbiasedMax(T), .safe));
        try expectEqual(exponentBiasedMax(T, .normal) / 2, exponentBiasFromUnbias(T, 0, .safe));
        try expectEqual(exponentBiasedMin(T, .normal), exponentBiasFromUnbias(T, exponentUnbiasedMin(T), .safe));
        // issue
        try expectError(error.OutsideBound, exponentBiasFromUnbias(T, exponentUnbiasedMax(T) + 1, .safe));
        try expectError(error.OutsideBound, exponentBiasFromUnbias(T, exponentUnbiasedMin(T) - 1, .safe));
    }
}

/// Convert a `bias_exp` to the unbiased version.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, single subtraction / few comparisons.
/// ExecMode:
/// - safe    | can throw error.
/// - uncheck | undefined when `bias_exp` is outside bound for `T_flt`.
/// Issue key specs:
/// - Throws *OutsideBound* when `bias_exp` is not within bound for `T_flt`.
pub inline fn exponentUnbiasFromBias(comptime T_flt: type, bias_exp: u16, comptime exec_mode: ExecMode) switch (exec_mode) {
    .uncheck => i16,
    .safe => ValueError!i16,
} {
    comptime assertType(T_flt, .{.float});

    switch (exec_mode) { // * comptime prune
        .uncheck => {
            @setRuntimeSafety(false);
            return @as(i16, @bitCast(bias_exp)) - exponentBias(T_flt);
        },
        .safe => {
            const bias_exp_max = exponentBiasedMax(T_flt, .normal);
            const bias_exp_min = exponentBiasedMin(T_flt, .normal);
            if (bias_exp > bias_exp_max or bias_exp < bias_exp_min) {
                return error.OutsideBound;
            }
            return @as(i16, @bitCast(bias_exp)) - exponentBias(T_flt);
        },
    }
}

test exponentUnbiasFromBias {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // ok
        try expectEqual(exponentUnbiasedMax(T), exponentUnbiasFromBias(T, exponentBiasedMax(T, .normal), .safe));
        try expectEqual(0, exponentUnbiasFromBias(T, exponentBiasedMax(T, .normal) / 2, .safe));
        try expectEqual(exponentUnbiasedMin(T), exponentUnbiasFromBias(T, exponentBiasedMin(T, .normal), .safe));
        // issue
        try expectError(error.OutsideBound, exponentUnbiasFromBias(T, exponentBiasedMax(T, .normal) + 1, .safe));
        try expectError(error.OutsideBound, exponentUnbiasFromBias(T, exponentBiasedMin(T, .normal) - 1, .safe));
    }
}

/// Constructs `T_flt` from its *components*.
/// Bit-pattern: [ sign-bit | exponent | "leading-bit" . fraction ]
/// Assumes *biased* `expo`, the `lead` only for *f80*.
/// Assumes `T_flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations.
pub inline fn construct(
    comptime T_flt: type,
    sign: u1,
    expo: u15,
    lead: u1,
    frac: TInt(.unsigned, fractionBitsN(TFloat(@bitSizeOf(T_flt)))),
) T_flt {
    const sign_sh: comptime_int = @typeInfo(T_flt).float.bits - 1;
    const expo_sh: comptime_int = mantissaBitsN(T_flt);
    switch (T_flt) { // * comptime prune
        f80 => {
            const lead_sh = fractionBitsN(T_flt);
            const pattern: u80 = @as(u80, sign) << sign_sh | @as(u80, expo) << expo_sh | @as(u80, lead) << lead_sh | @as(u80, frac);
            return @bitCast(pattern);
        },
        else => {
            const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
            const pattern: T_bits = @as(T_bits, sign) << sign_sh | @as(T_bits, expo) << expo_sh | @as(T_bits, frac);
            return @bitCast(pattern);
        },
    }
}

/// Returns the biggest value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, comptime-defined constant.
pub inline fn max(comptime T_flt: type) T_flt {
    comptime assertType(T_flt, .{.float});
    return construct(T_flt, 0, exponentBiasedMax(T_flt, .normal), 0, fractionMax(T_flt));
}

test max {}

/// Returns the smallest value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, comptime-defined constant.
pub inline fn min(comptime T_flt: type, comptime mode: enum { normal, subnormal }) T_flt {
    comptime assertType(T_flt, .{.float});
    return switch (mode) { // * comptime prune
        .normal => construct(T_flt, 1, exponentBiasedMax(T_flt, .normal), 0, 0),
        .subnormal => construct(T_flt, 0, exponentBiasedMin(T_flt, .special), 0, 1),
    };
}

test min {}

/// Returns the canonical NaN for `T_flt`.
/// `mode` *.Quiet* (qNaN), most common, doesn't raise exception when used.
/// `mode` *.Signaling* (sNaN), raises an exception when used in operations.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, pre-defined constant.
pub inline fn nan(comptime T_flt: type, comptime sign: enum { positive, negative }, comptime mode: enum { quiet, signaling }) T_flt {
    comptime assertType(T_flt, .{.float});
    // * comptime prune \/
    const s = if (sign == .negative) 1 else 0;
    const l = if (T_flt == f80) 1 else 0;
    const f = if (mode == .quiet) fractionNanQuiet(T_flt) else fractionNanSignaling(T_flt);
    return construct(T_flt, s, exponentBiasedMax(T_flt, .special), l, f);
}

test nan {}

/// Returns the inf-value for `T_flt`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, comptime-defined constant.
pub inline fn inf(comptime T_flt: type, comptime sign: enum { positive, negative }) T_flt {
    comptime assertType(T_flt, .{.float});
    // * comptime prune \/
    const s = if (sign == .negative) 1 else 0;
    const l = if (T_flt == f80) 1 else 0;
    return construct(T_flt, s, exponentBiasedMax(T_flt, .special), l, 0);
}

test inf {}

/// Check if `flt` is *normal*, *subnormal* or *zero*.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations.
pub inline fn isFinite(flt: anytype) bool {
    comptime assertType(@TypeOf(flt), .{.float});

    const T_flt = @TypeOf(flt);
    const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
    const flt_bit_oper: T_bits = @bitCast(flt);
    const inf_bit_oper: T_bits = @bitCast(inf(T_flt, .positive));
    const bitmask_no_sign = ~@as(T_bits, 0) >> 1;

    return ((flt_bit_oper & bitmask_no_sign) < inf_bit_oper);
}

test isFinite {
    @setEvalBranchQuota(1500);
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // normals
        try expectEqual(true, isFinite(min(T, .normal)));
        try expectEqual(true, isFinite(max(T)));
        // zero & subnormal
        try expectEqual(true, isFinite(@as(T, 0.0)));
        try expectEqual(true, isFinite(@as(T, -0.0)));
        try expectEqual(true, isFinite(min(T, .subnormal)));
        // inf & nan
        try expectEqual(false, isFinite(inf(T, .positive)));
        try expectEqual(false, isFinite(inf(T, .negative)));
        try expectEqual(false, isFinite(nan(T, .negative, .quiet)));
        try expectEqual(false, isFinite(nan(T, .negative, .signaling)));
    }
}

/// Check if `flt` is neither *zero*, *subnormal*, *infinity* or *NaN*.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations and comparison.
pub inline fn isNormal(flt: anytype) bool {
    comptime assertType(@TypeOf(flt), .{.float});

    const T_flt = @TypeOf(flt);
    const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
    const flt_bit_oper: T_bits = @bitCast(flt);
    const bitmask_no_sign = ~@as(T_bits, 0) >> 1;
    const exp_incrementer = 1 << mantissaBitsN(T_flt);

    // Add 1 to the exponent, if it overflows to 0 or becomes 1,
    // then it was all ones (inf/nan) or all zeroes (zero/subnormal).
    // The sign bit is removed because all ones would overflow into it.
    // For f80, even though it has an explicit leading-bit stored,
    // the exponent takes priority due to its higher significance.
    return ((bitmask_no_sign & (flt_bit_oper +% exp_incrementer)) >= (exp_incrementer << 1));
}

test isNormal {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // normals
        try expectEqual(true, isNormal(min(T, .normal)));
        try expectEqual(true, isNormal(max(T)));
        // zero & subnormal
        try expectEqual(false, isNormal(@as(T, 0.0)));
        try expectEqual(false, isNormal(@as(T, -0.0)));
        try expectEqual(false, isNormal(min(T, .subnormal)));
        // inf & nan
        try expectEqual(false, isNormal(inf(T, .positive)));
        try expectEqual(false, isNormal(inf(T, .negative)));
        try expectEqual(false, isNormal(nan(T, .positive, .quiet)));
        try expectEqual(false, isNormal(nan(T, .negative, .quiet)));
    }
}

/// Check if `flt` is neither *subnormal*, *infinity* or *NaN*.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, few bitwise operations and comparison.
pub inline fn isNormalOrZero(flt: anytype) bool {
    comptime assertType(@TypeOf(flt), .{.float});
    return (flt == 0) or isNormal(flt);
}

test isNormalOrZero {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // normals
        try expectEqual(true, isNormalOrZero(min(T, .normal)));
        try expectEqual(true, isNormalOrZero(max(T)));
        // zero & subnormal
        try expectEqual(true, isNormalOrZero(@as(T, 0.0)));
        try expectEqual(true, isNormalOrZero(@as(T, -0.0)));
        try expectEqual(false, isNormalOrZero(min(T, .subnormal)));
        // inf & nan
        try expectEqual(false, isNormalOrZero(inf(T, .positive)));
        try expectEqual(false, isNormalOrZero(inf(T, .negative)));
        try expectEqual(false, isNormalOrZero(nan(T, .positive, .quiet)));
        try expectEqual(false, isNormalOrZero(nan(T, .negative, .quiet)));
    }
}

/// Check if `flt` is a specific zero-value.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, single comparison / few bitsise operations.
pub inline fn isZero(flt: anytype, comptime mode: enum { positive, negative, both }) bool {
    comptime assertType(@TypeOf(flt), .{.float});
    switch (mode) { // * comptime prune
        .both => return (flt == 0),
        else => {
            const T_flt = @TypeOf(flt);
            const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
            const flt_bit_oper: T_bits = @bitCast(flt);
            return switch (mode) { // * comptime prune
                .positive => (flt_bit_oper == 0),
                .negative => (flt_bit_oper == (1 << @typeInfo(T_flt).float.bits - 1)),
                else => unreachable,
            };
        },
    }
}

test isZero {
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // true
        try expectEqual(true, isZero(@as(T, 0.0), .both));
        try expectEqual(true, isZero(@as(T, -0.0), .both));
        try expectEqual(true, isZero(@as(T, 0.0), .positive));
        try expectEqual(true, isZero(@as(T, -0.0), .negative));
        // false
        try expectEqual(false, isZero(@as(T, 4.0), .both));
        try expectEqual(false, isZero(@as(T, -0.0), .positive));
        try expectEqual(false, isZero(@as(T, 4.0), .positive));
        try expectEqual(false, isZero(@as(T, 0.0), .negative));
        try expectEqual(false, isZero(@as(T, 4.0), .negative));
    }
}

/// Check if `flt` is some NaN.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, single comparison / few bitwise operations.
pub inline fn isNan(flt: anytype, comptime sign: enum { positive, negative, both }, comptime mode: enum { quiet, signaling, both }) bool {
    comptime assertType(@TypeOf(flt), .{.float});

    const T_flt = @TypeOf(flt);
    const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
    const flt_bit_oper: T_bits = @bitCast(flt);
    const sign_bit_mask = 1 << (@typeInfo(T_flt).float.bits - 1);

    const is_nan = switch (mode) { // * comptime prune
        .both => (flt != flt),
        .quiet => (flt != flt) and (flt_bit_oper & fractionNanQuiet(T_flt)) != 0,
        .signaling => (flt != flt) and (flt_bit_oper & fractionNanQuiet(T_flt)) == 0,
    };

    return switch (sign) { // * comptime prune
        .both => is_nan,
        .positive => is_nan and (flt_bit_oper & sign_bit_mask) == 0,
        .negative => is_nan and (flt_bit_oper & sign_bit_mask) != 0,
    };
}

test isNan {
    @setEvalBranchQuota(2000);
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // true
        try expectEqual(true, isNan(nan(T, .positive, .quiet), .positive, .both));
        try expectEqual(true, isNan(nan(T, .positive, .signaling), .positive, .both));
        try expectEqual(true, isNan(nan(T, .positive, .quiet), .positive, .quiet));
        try expectEqual(true, isNan(nan(T, .positive, .signaling), .positive, .signaling));
        //
        try expectEqual(true, isNan(nan(T, .negative, .quiet), .both, .quiet));
        try expectEqual(true, isNan(nan(T, .negative, .quiet), .negative, .quiet));
        // false
        try expectEqual(false, isNan(@as(T, 4.0), .both, .both));
        try expectEqual(false, isNan(nan(T, .positive, .signaling), .both, .quiet));
        try expectEqual(false, isNan(@as(T, 4.0), .both, .quiet));
        try expectEqual(false, isNan(nan(T, .positive, .quiet), .both, .signaling));
        try expectEqual(false, isNan(@as(T, 4.0), .both, .signaling));
    }
}

/// Check if `flt` is some infinity.
/// Asserts `flt` to be a *float* type.
/// Compute - *very cheap*, single comparison / few bitwise operations.
pub inline fn isInf(flt: anytype, comptime sign: enum { positive, negative, both }) bool {
    comptime assertType(@TypeOf(flt), .{.float});
    const T_flt = @TypeOf(flt);
    switch (sign) { // * comptime prune
        .both => {
            const T_bits = TInt(.unsigned, @typeInfo(T_flt).float.bits);
            const flt_bit_oper: T_bits = @bitCast(flt);
            const inf_bit_oper: T_bits = @bitCast(inf(T_flt, .positive));
            const bitmask_no_sign = ~@as(T_bits, 0) >> 1;
            return (flt_bit_oper & bitmask_no_sign) == inf_bit_oper;
        },
        .positive, .negative => {
            return flt == comptime inf(T_flt, @enumFromInt(@intFromEnum(sign)));
        },
    }
}

test isInf {
    @setEvalBranchQuota(2000);
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |T| {
        // true
        try expectEqual(true, isInf(inf(T, .positive), .both));
        try expectEqual(true, isInf(inf(T, .negative), .both));
        try expectEqual(true, isInf(inf(T, .positive), .positive));
        try expectEqual(true, isInf(inf(T, .negative), .negative));
        // false
        try expectEqual(false, isInf(@as(T, 4.0), .both));
        try expectEqual(false, isInf(inf(T, .negative), .positive));
        try expectEqual(false, isInf(@as(T, 4.0), .positive));
        try expectEqual(false, isInf(inf(T, .positive), .negative));
        try expectEqual(false, isInf(@as(T, 4.0), .negative));
    }
}

/// Returns the sum of `a` + `b`.
/// Asserts `T_flt` to be a *float* type.
/// Compute - *very cheap*, basic operation and comparison
/// Issue key specs:
/// - Throws *Overflow* when result would be *non-finite*.
pub inline fn checkedAdd(comptime T_flt: type, a: T_flt, b: T_flt) ValueError!T_flt {
    comptime assertType(T_flt, .{ .float, .comptime_float });
    switch (T_flt) { // * comptime prune
        comptime_float => return a + b,
        else => {
            const result = a + b;
            return if (isFinite(result)) result else error.Overflow;
        },
    }
}

test checkedAdd {
    try expectEqual(7.0, checkedAdd(f16, 4.0, 3.0));
    try expectEqual(error.Overflow, checkedAdd(f16, 32768, 32768));
}

/// Returns the product of `a` * `b`.
/// Asserts `T_flt` to be an *float* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *Overflow* when result would be *non-finite*.
pub inline fn checkedMul(comptime T_flt: type, a: T_flt, b: T_flt) ValueError!T_flt {
    comptime assertType(T_flt, .{ .float, .comptime_float });
    switch (T_flt) { // * comptime prune
        comptime_float => return a * b,
        else => {
            const result = a * b;
            return if (isFinite(result)) result else error.Overflow;
        },
    }
}

test checkedMul {
    try expectEqual(12.0, checkedMul(f16, 4.0, 3.0));
    try expectError(error.Overflow, checkedMul(f16, 256, 256));
}

/// Returns the difference of `a` - `b`.
/// Asserts `T_flt` to be an *float* type.
/// Compute - *very cheap*, basic operation and comparison.
/// Issue key specs:
/// - Throws *Underflow* when result would be *non-finite*.
pub inline fn checkedSub(comptime T_flt: type, a: T_flt, b: T_flt) ValueError!T_flt {
    comptime assertType(T_flt, .{ .float, .comptime_float });
    switch (T_flt) { // * comptime prune
        comptime_float => return a - b,
        else => {
            const result = a - b;
            return if (isFinite(result)) result else error.Underflow;
        },
    }
}

test checkedSub {
    try expectEqual(1.0, checkedSub(f16, 4.0, 3.0));
    try expectError(error.Underflow, checkedSub(f16, -32768, 32768));
}
