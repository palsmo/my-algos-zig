const misc = @import("./misc.zig");

// exports -->

// misc
pub const assertAndMsg = misc.assertAndMsg;
pub const assertComptime = misc.assertComptime;

// testing -->

test {
    _ = misc;
}
