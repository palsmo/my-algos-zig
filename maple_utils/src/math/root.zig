const misc = @import("./misc.zig");
const shared = @import("./shared.zig");

// exports -->

pub const Error = shared.Error;
pub const assertPowOf2 = misc.assertPowOf2;
pub const fastMod = misc.fastMod;
pub const getPow10 = misc.getPow10;
pub const isPowOf2 = misc.isPowOf2;
pub const mulPercent = misc.mulPercent;
pub const power_of_10_table_float = misc.power_of_10_table_float;
pub const power_of_10_table_int = misc.power_of_10_table_int;
pub const wrapDecrement = misc.wrapDecrement;
pub const wrapIncrement = misc.wrapIncrement;

// testing -->

test {
    _ = misc;
}
