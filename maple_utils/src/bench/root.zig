//! Author: palsmo
//! Status: Done
//! About: Root Benchmark Functionality

const root_misc = @import("./misc.zig");

// exports -->

pub const misc = struct {
    pub const benchmark = root_misc.benchmark;
    pub const benchmarkPrint = root_misc.benchmarkPrint;
};

// testing -->

test {
    _ = root_misc;
}
