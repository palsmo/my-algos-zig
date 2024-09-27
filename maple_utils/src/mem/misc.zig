//! Author: palsmo
//! Status: Done

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertType = mod_assert.assertType;
const assertTypeSame = mod_assert.assertTypeSame;
const expectEqual = std.testing.expectEqual;

/// Inline swap values `a` <-> `b`.
/// Asserts `a` and `b` to be pointers of same type.
pub inline fn swap(a: anytype, b: anytype) void {
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{.pointer});

    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

test swap {
    var before = [_]u8{ 1, 2 };
    const after = [_]u8{ 2, 1 };
    swap(&before[0], &before[1]);
    try expectEqual(after, before);
}
