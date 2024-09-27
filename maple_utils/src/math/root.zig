//! Author: palsmo
//! Status: In Progress
//! About: Root Maths Library
//!
//! Computation Scale:
//!
//!  computation  |                           examples
//! --------------|---------------------------------------------------------------
//! very cheap    | few additions, multiplications and logic operations
//! cheap         | simple arithmetic with subtractions and division
//! moderate      | basic calculus, linear algebra, sqrt, cos, sin, tan, mod, log
//! expensive     | bigger matrix operations, numeric integration, FFT
//! heavy         | differential equations, iterative processes
//! very heavy    | complex simulations, cryptography, machine learning
//! ------------------------------------------------------------------------------

const root_float = @import("./float.zig");
const root_int = @import("./int.zig");
const root_linear = @import("./linear.zig");
const root_misc = @import("./misc.zig");

// exports -->

pub const float = struct {
    pub const POWER_OF_10_TABLE = root_float.POWER_OF_10_TABLE;
    pub const construct = root_float.construct;
    pub const exponentBitsN = root_float.exponentBitsN;
    pub const exponentBiasedMax = root_float.exponentBiasedMax;
    pub const exponentBiasedMin = root_float.exponentBiasedMin;
    pub const exponentUnbiasedMax = root_float.exponentUnbiasedMax;
    pub const exponentUnbiasedMin = root_float.exponentUnbiasedMin;
    pub const exponentBias = root_float.exponentBias;
    pub const exponentBiasFromUnbias = root_float.exponentBiasFromUnbias;
    pub const exponentUnbiasFromBias = root_float.exponentUnbiasFromBias;
    pub const fractionBitsN = root_float.fractionBitsN;
    pub const fractionMax = root_float.fractionMax;
    pub const fractionMin = root_float.fractionMin;
    pub const fractionNanQuiet = root_float.fractionNanQuiet;
    pub const fractionNanSignaling = root_float.fractionNanSignaling;
    pub const mantissaBitsN = root_float.mantissaBitsN;
    pub const mantissaMax = root_float.mantissaMax;
    pub const mantissaMin = root_float.mantissaMin;
    pub const max = root_float.max;
    pub const min = root_float.min;
    pub const nan = root_float.nan;
    pub const inf = root_float.inf;
    pub const isFinite = root_float.isFinite;
    pub const isNormal = root_float.isNormal;
    pub const isNormalOrZero = root_float.isNormalOrZero;
    pub const isZero = root_float.isZero;
    pub const isNan = root_float.isNan;
    pub const isInf = root_float.isInf;
    pub const checkedAdd = root_float.checkedAdd;
    pub const checkedMul = root_float.checkedMul;
    pub const checkedSub = root_float.checkedSub;
    pub const isPowerOf2 = root_float.isPowerOf2;
    pub const nextPowerOf2 = root_float.nextPowerOf2;
};

pub const int = struct {
    pub const POWER_OF_10_TABLE = root_int.POWER_OF_10_TABLE;
    pub const max = root_int.max;
    pub const min = root_int.min;
    pub const checkedAdd = root_int.checkedAdd;
    pub const checkedMul = root_int.checkedMul;
    pub const checkedSub = root_int.checkedSub;
    pub const fastMod = root_int.fastMod;
    pub const isPowerOf2 = root_int.isPowerOf2;
    pub const nextPowerOf2 = root_int.nextPowerOf2;
    pub const nthPower10 = root_int.nthPower10;
    pub const minRepBits = root_int.minBits;
};

pub const linear = struct {
    pub const cross = root_linear.cross;
    pub const dot = root_linear.dot;
    pub const length = root_linear.length;
    pub const norm = root_linear.norm;
};

pub const misc = struct {
    pub const mulPercent = root_misc.mulPercent;
    pub const wrapDecrement = root_misc.wrapDecrement;
    pub const wrapIncrement = root_misc.wrapIncrement;
};

// testing -->

test {
    _ = root_float;
    _ = root_int;
    _ = root_misc;
    //_ = root_linear;
}
