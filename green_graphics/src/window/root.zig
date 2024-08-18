//! Author: palsmo
//! Status: Done
//! About: Root File Window Functionality

const root_misc = @import("./window.zig");
const root_shared = @import("./shared.zig");

// exports -->

pub const misc = struct {
    pub const WindowHandler = root_misc.WindowHandler;
    pub const XClientError = root_shared.XClientError;
    pub const WClientError = root_shared.WClientError;
};

// testing -->

test {
    _ = root_misc;
    _ = root_shared;
}
