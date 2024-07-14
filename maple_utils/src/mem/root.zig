const compare = @import("./compare.zig");
const misc = @import("./misc.zig");

// exports -->

pub const cmd = compare.cmp;
pub const ord = compare.ord;
pub const swap = misc.swap;

// testing -->

test {
    _ = compare;
    _ = misc;
}
