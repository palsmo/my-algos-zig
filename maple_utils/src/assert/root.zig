//! Author: palsmo
//! Status: Done
//! About: Root File Assert Functionality

const root_misc = @import("./misc.zig");

// exports -->

pub const assertAndMsg = root_misc.assertAndMsg;
pub const assertComptime = root_misc.assertComptime;
pub const assertFn = root_misc.assertFn;
pub const assertPowerOf2 = root_misc.assertPowerOf2;
pub const assertType = root_misc.assertType;
pub const assertTypeSame = root_misc.assertTypeSame;

// testing -->

test {
    _ = root_misc;
}
