//! Author: palsmo
//! Status: Done

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertType = mod_assert.misc.assertType;
const assertTypeSame = mod_assert.misc.assertTypeSame;
const expectEqual = std.testing.expectEqual;

/// Inline swap values `a` <-> `b`.
/// Asserts `a` and `b` to be pointers of same type.
pub inline fn swap(a: anytype, b: anytype) void {
    comptime assertTypeSame(@TypeOf(a), @TypeOf(b));
    comptime assertType(@TypeOf(a), .{.Pointer}, "fn {s}.a", .{@src().fn_name});

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
