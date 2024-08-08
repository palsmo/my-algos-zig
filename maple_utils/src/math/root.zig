//! Author: palsmo
//! Status: In Progress
//! About: Maths Library Root
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

const _linear = @import("./linear.zig");
const _misc = @import("./misc.zig");
const shared = @import("./shared.zig");

// exports -->

// shared
pub const err = struct {
    pub const ValueError = shared.ValueError;
};

// miscellaneous
pub const misc = struct {
    pub const fastMod = _misc.fastMod;
    pub const indexPower10 = _misc.indexPower10;
    pub const isPowerOf2 = _misc.isPowerOf2;
    pub const mulPercent = _misc.mulPercent;
    pub const power_of_10_table_float = _misc.power_of_10_table_float;
    pub const power_of_10_table_int = _misc.power_of_10_table_int;
    pub const safeAdd = _misc.safeAdd;
    pub const safeMul = _misc.safeMul;
    pub const safeSub = _misc.safeSub;
    pub const wrapDecrement = _misc.wrapDecrement;
    pub const wrapIncrement = _misc.wrapIncrement;
};

// linear algebra
pub const linear = struct {
    pub const dot = _linear.dot;
    pub const cross = _linear.cross;
    pub const norm = _linear.norm;
    pub const length = _linear.length;
};

// testing -->

test {
    //_ = linear;
    _ = _misc;
}
