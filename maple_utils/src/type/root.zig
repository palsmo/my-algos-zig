//! About: palsmo
//! Status: In Progress
//! About: Root Types Library

const root_misc = @import("./misc.zig");

// exports -->

pub const misc = struct {
    pub const TFloat = root_misc.TFloat;
    pub const TInt = root_misc.TInt;
    pub const Child = root_misc.Child;
    pub const NextPowerOf2 = root_misc.NextPowerOf2;
    pub const PointerArrayChildType = root_misc.PointerArrayChildType;
    pub const isString = root_misc.isString;
    pub const verifyContext = root_misc.verifyContext;
};

// testing -->

test {
    _ = root_misc;
}
