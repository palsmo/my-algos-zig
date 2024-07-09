const std = @import("std");

const assert = std.debug.assert;

/// Stable, in-place, best case O(n), average and worst case O(n^2).
/// Most efficient for small (<100 items) data sets and those substantially sorted.
/// Not efficient for big+ data sets (>10_000 items).
/// Memory consumption is O(1) during and O(1) post.
pub fn sort(comptime T: type, items: []T) void {
    @call(.always_inline, sortLoop, .{ T, items, items.len });
}

/// Same as `sort` but has the option to only sort the first `n` items.
/// Specify `n` as 'items.len' or 'null' for whole array.
pub fn sortN(comptime T: type, n: ?usize, items: []T) void {
    @call(.always_inline, sortLoop, .{ T, items, n });
}

/// The sorting algorithm implemented with looping.
/// Sorts the first `n` items in `items`, null == 'items.len'.
fn sortLoop(comptime T: type, items: []T, n: ?usize) void {
    if (items.len <= 1) return;
    @call(.always_inline, driveLoop, .{ T, n orelse items.len, items });
}

/// Drivetrain for the sorting algorithm.
/// Iterating `n` times results `n` items being sorted.
fn driveLoop(comptime T: type, n: usize, items: []T) void {
    for (1..n) |i| {
        const key = items[i];
        var j = i;
        while (j > 0 and items[j - 1] > key) : (j -= 1) {
            // shift elements to the right to clear a spot for key
            items[j] = items[j - 1];
        }
        items[j] = key;
    }
}

// testing -->

const testing = @import("./testing.zig");

test sort {
    try testing.sort_array_empty(sort, .{});
    try testing.sort_array_single(sort, .{});
    try testing.sort_array_same(sort, .{});
    try testing.sort_array_sorted(sort, .{});
    try testing.sort_array_reverse(sort, .{});
    try testing.sort_array_unsorted(sort, .{});

    try testing.sort_array_unsorted(sortLoop, .{null});
}
