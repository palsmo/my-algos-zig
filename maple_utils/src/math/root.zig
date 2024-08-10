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

const root_linear = @import("./linear.zig");
const root_misc = @import("./misc.zig");
const root_prim = @import("./primitive.zig");
const shared = @import("./shared.zig");

// exports -->

pub const err = struct {
    pub const ValueError = shared.ValueError;
};

pub const prim = struct {
    pub const safeAdd = root_prim.safeAdd;
    pub const safeMul = root_prim.safeMul;
    pub const safeSub = root_prim.safeSub;
    pub const fastMod = root_prim.fastMod;
    pub const indexPower10 = root_prim.indexPower10;
    pub const power_of_10_table_float = root_prim.power_of_10_table_float;
    pub const power_of_10_table_int = root_prim.power_of_10_table_int;
};

pub const misc = struct {
    pub const isPowerOf2 = root_misc.isPowerOf2;
    pub const mulPercent = root_misc.mulPercent;
    pub const wrapDecrement = root_misc.wrapDecrement;
    pub const wrapIncrement = root_misc.wrapIncrement;
};

pub const linear = struct {
    pub const dot = root_linear.dot;
    pub const cross = root_linear.cross;
    pub const norm = root_linear.norm;
    pub const length = root_linear.length;
};

// testing -->

test {
    //_ = linear;
    _ = root_misc;
    _ = root_prim;
}
