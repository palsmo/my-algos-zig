const std = @import("std");

const utility = @import("utility");

const assert = std.debug.assert;
const assert_array_pointer_type = utility.assert_array_pointer_type;

/// Stable, in-place, best case O(n), average and worst case O(n^2).
/// Most efficient for tiny (<20 items) data sets or those substantially sorted.
/// Not efficient for small+ data sets (>100 items).
/// Memory consumption is O(1) during and O(1) post.
pub fn sort(items: anytype) void {
    @call(.always_inline, sort_loop, .{items});
}

/// The sorting algorithm implemented with looping.
pub fn sort_loop(items: anytype) void {
    _ = assert_array_pointer_type(@TypeOf(items));

    if (items.len <= 1) return;

    drive_loop(items);
}

/// Drivetrain for the sorting algorithm.
inline fn drive_loop(items: anytype) void {
    var len = items.len;
    var swapped = true;

    while (swapped) {
        swapped = false;

        // optimization - after each full pass the largest element among
        // the unsorted "bubbles up" to its correct position at the end,
        // by scoping the proceeding passes these elements won't be
        // unnecessary compaired again.
        len -= 1;

        for (0..len) |i| {
            const current = i;
            const next = i + 1;
            if (items[current] > items[next]) {
                // swapping
                const tmp = items[current].*;
                items[current].* = items[next].*;
                items[next].* = tmp;
                swapped = true;
            }
        }
    }
}

// testing -->

const testing = @import("./testing.zig");

test sort {
    try testing.test_sort_array_empty(sort, .{});
    try testing.test_sort_array_single(sort, .{});
    try testing.test_sort_array_same(sort, .{});
    try testing.test_sort_array_sorted(sort, .{});
    try testing.test_sort_array_reverse(sort, .{});
    try testing.test_sort_array_unsorted(sort, .{});

    try testing.test_sort_array_unsorted(sort_loop, .{});
}
