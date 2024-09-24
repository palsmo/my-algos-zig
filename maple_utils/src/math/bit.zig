// Author: palsmo

const std = @import("std");

pub inline fn ones(comptime n: comptime_int) comptime_int {
    return (1 << n) - 1;
}
