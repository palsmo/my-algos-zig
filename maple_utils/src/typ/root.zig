//! About: palsmo
//! Status: In Progress
//! About: Root Types Library

const root_misc = @import("./misc.zig");

// exports -->

pub const misc = struct {
    pub const PointerArrayChildType = root_misc.PointerArrayChildType;
    pub const T_float = root_misc.T_float;
    pub const T_int = root_misc.T_int;
    pub const isString = root_misc.isString;
    pub const verifyContext = root_misc.verifyContext;
};

// testing -->

test {
    _ = root_misc;
}
