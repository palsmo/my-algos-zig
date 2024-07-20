//! Author: palsmo

const robin = @import("./robin_hashmap.zig");
const shared = @import("./shared.zig");

// exports -->

pub const RobinHashMap = robin.RobinHashMap;
pub const Error = shared.Error;

// testing -->

test {
    _ = robin;
}
