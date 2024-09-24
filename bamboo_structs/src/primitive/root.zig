//! Author: palsmo
//! Status: Done

const root_cbuf = @import("./circular_buffer.zig");

// exports -->

pub const misc = struct {
    pub const CircularBuffer = root_cbuf.CircularBuffer;
};

// testing -->

test {
    _ = root_cbuf;
}
