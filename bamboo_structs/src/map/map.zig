const robin = @import("./robin_hashmap.zig");

// exports -->

pub const RobinHashMap = robin.RobinHashMap;

pub const Error = error{
    CapacityReached,
    ProbeDistanceOverflow,
};

// testing -->

test {
    _ = robin;
}
