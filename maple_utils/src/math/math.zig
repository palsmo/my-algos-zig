const misc = @import("./misc.zig");

// exports -->

//pub const entropy = misc.entropy;
pub const mulPercent = misc.mulPercent;

pub const Error = error{
    Overflow,
};

// testing -->

test {
    _ = misc;
}
