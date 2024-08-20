const std = @import("std");

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const ARRAY_EMPTY: [0]u8 = .{};
const ARRAY_SINGLE: [1]u8 = .{4};
const ARRAY_SAME: [4]u8 = .{ 4, 4, 4, 4 };
const ARRAY_SORTED: [9]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
const ARRAY_REVERSED: [9]u8 = .{ 9, 8, 7, 6, 5, 4, 3, 2, 1 };
const ARRAY_UNSORTED: [9]u8 = .{ 5, 8, 1, 2, 7, 4, 3, 6, 9 };

pub fn call_sort(comptime T: type, sort_fn: anytype, items: []T, args: anytype) !void {
    const sort_fn_info = @typeInfo(@TypeOf(sort_fn));
    assert(sort_fn_info == .Fn);

    if (sort_fn_info.Fn.return_type == void) {
        @call(.auto, sort_fn, .{ T, items } ++ args);
    } else {
        try @call(.auto, sort_fn, .{ T, items } ++ args);
    }
}

pub fn sort_array_empty(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_EMPTY;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    try expectEqual(0, items.len);
}

pub fn sort_array_single(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_SINGLE;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    try expectEqual(4, items[0]);
}

pub fn sort_array_same(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_SAME;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    for (items) |e| try expectEqual(4, e);
}

pub fn sort_array_sorted(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_SORTED;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    for (items, 1..) |e, i| try expectEqual(i, e);
}

pub fn sort_array_reverse(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_REVERSED;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    for (items, 1..) |e, i| try expectEqual(i, e);
}

pub fn sort_array_unsorted(sort_fn: anytype, args: anytype) !void {
    var items = ARRAY_UNSORTED;
    const C = std.meta.Child(@TypeOf(items));
    try call_sort(C, sort_fn, &items, args);
    for (items, 1..) |e, i| try expectEqual(i, e);
}
