const misc = @import("./misc.zig");
const shared = @import("./shared.zig");

// exports -->

pub const Error = shared.Error;
pub const mulPercent = misc.mulPercent;
pub const wrapDecrement = misc.wrapDecrement;
pub const wrapIncrement = misc.wrapIncrement;

// testing -->

test {
    _ = misc;
}
