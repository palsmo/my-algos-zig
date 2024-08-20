//! Author: palsmo
//! Status: Done
//! About: Root File Input Functionality

const root_misc = @import("./misc.zig");
const root_shared = @import("./shared.zig");

// exports -->

pub const misc = struct {
    pub const InputHandler = root_misc.InputHandler;
    pub const InputError = root_shared.InputError;
};

// testing -->

test {
    _ = root_misc;
    _ = root_shared;
}
