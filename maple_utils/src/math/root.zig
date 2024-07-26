//! Author: palsmo
//! Status: In Progress
//! About: Maths Library Root
//!
//! Computation scale/table:
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

const linear = @import("./linear.zig");
const misc = @import("./misc.zig");
const shared = @import("./shared.zig");

// exports -->

// shared
pub const Error = shared.Error;

// misc
pub const assertPowOf2 = misc.assertPowOf2;
pub const fastMod = misc.fastMod;
pub const getPow10 = misc.getPow10;
pub const isPowOf2 = misc.isPowOf2;
pub const mulPercent = misc.mulPercent;
pub const power_of_10_table_float = misc.power_of_10_table_float;
pub const power_of_10_table_int = misc.power_of_10_table_int;
pub const wrapDecrement = misc.wrapDecrement;
pub const wrapIncrement = misc.wrapIncrement;

// linear
pub const dot = linear.dot;
pub const cross = linear.cross;
pub const norm = linear.norm;
pub const length = linear.length;

// testing -->

test {
    _ = linear;
    _ = misc;
}
