//! Author: palsmo
//! Status: In Progress

const std = @import("std");

const expectEqual = std.testing.expectEqual;

/// Inline swap values `a` <-> `b`.
pub inline fn swap(comptime T: type, a: *T, b: *T) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

test swap {
    const T = u8;
    var before: [2]T = .{ 1, 2 };
    const after: [2]T = .{ 2, 1 };
    swap(T, &before[0], &before[1]);
    try expectEqual(after, before);
}
