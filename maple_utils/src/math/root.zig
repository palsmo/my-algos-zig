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
const root_linear = @import("./linear.zig");
const root_misc = @import("./misc.zig");
const root_prim = @import("./primitive.zig");
const root_shared = @import("./shared.zig");

// exports -->

pub const err = struct {
    pub const ValueError = root_shared.ValueError;
};

pub const float = struct {
    pub const construct = root_float.construct;
    pub const exponentBias = root_float.exponentBias;
    pub const exponentBiasFromUnbias = root_float.exponentBiasFromUnbias;
    pub const exponentBitsN = root_float.exponentBitsN;
    pub const exponentMax = root_float.exponentMax;
    pub const exponentMin = root_float.exponentMin;
    pub const fractionalBitsN = root_float.fractionalBitsN;
    pub const inf = root_float.inf;
    pub const isInf = root_float.isInf;
    pub const isNan = root_float.isNan;
    pub const mantissaBitsN = root_float.mantissaBitsN;
    pub const mantissaMax = root_float.mantissaMax;
    pub const mantissaMin = root_float.mantissaMin;
    pub const nan = root_float.nan;
};

pub const linear = struct {
    pub const cross = root_linear.cross;
    pub const dot = root_linear.dot;
    pub const length = root_linear.length;
    pub const norm = root_linear.norm;
};

pub const misc = struct {
    pub const isPowerOf2 = root_misc.isPowerOf2;
    pub const mulPercent = root_misc.mulPercent;
    pub const wrapDecrement = root_misc.wrapDecrement;
    pub const wrapIncrement = root_misc.wrapIncrement;
};

pub const prim = struct {
    pub const fastMod = root_prim.fastMod;
    pub const indexPower10 = root_prim.indexPower10;
    pub const power_of_10_table_float = root_prim.power_of_10_table_float;
    pub const power_of_10_table_int = root_prim.power_of_10_table_int;
    pub const safeAdd = root_prim.safeAdd;
    pub const safeMul = root_prim.safeMul;
    pub const safeSub = root_prim.safeSub;
};

// testing -->

test {
    //_ = linear;
    _ = root_float;
    _ = root_misc;
    _ = root_prim;
    _ = root_shared;
}
