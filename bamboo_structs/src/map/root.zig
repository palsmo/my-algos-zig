//! Author: palsmo

const robin = @import("./robin_hashmap.zig");
const shared = @import("./shared.zig");

// exports -->

pub const RobinHashMap = robin.RobinHashMap;

// testing -->

test {
    _ = robin;
}
