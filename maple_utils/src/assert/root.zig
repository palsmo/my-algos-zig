//! Author: palsmo
//! Status: Done
//! About: Assert Functionality

const _misc = @import("./misc.zig");

// exports -->

// miscellaneous
pub const misc = struct {
    pub const assertAndMsg = _misc.assertAndMsg;
    pub const assertComptime = _misc.assertComptime;
    pub const assertFn = _misc.assertFn;
    pub const assertPowOf2 = _misc.assertPowOf2;
    pub const assertType = _misc.assertType;
};

// testing -->

test {
    _ = _misc;
}
