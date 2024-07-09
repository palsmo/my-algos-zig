const misc = @import("./misc.zig");

// exports -->

pub const entropy = misc.entropy;

// testing -->

test {
    _ = misc;
}
