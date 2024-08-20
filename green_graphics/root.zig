//! Author: palsmo
//! Status: In Progress
//! About: Root File Green Graphics

pub const window = @import("./src/window/root.zig");
pub const input = @import("./src/input/root.zig");

test {
    _ = window;
}
