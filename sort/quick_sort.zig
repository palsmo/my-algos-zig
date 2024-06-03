const std = @import("std");
const builtin = std.builtin;
const mem = std.mem;

/// Stable in-place sort. O(n) best case, O(n log(n)) worst case.
fn quickSort(comptime T: type, items: []T, lo: usize, hi: usize) void {
    if (lo < hi) {
        const p = partition(T, items, lo, hi);
        quickSort(T, items, lo, @min(p, p -% 1));
        quickSort(T, items, p + 1, hi);
    }
}

/// Hoare's partition scheme with median-of-three-pivot
fn partition(comptime T: type, items: []T, lo: usize, hi: usize) usize {
    const mi = lo + (hi - lo) / 2; // overflow protect

    // balanced pivot results in the best performance,
    // especially on already ordered arrays that would
    // otherwise be O(n^2) complexity
    const mi_less_lo = items[mi] < items[lo];
    const lo_less_hi = items[lo] < items[hi];
    const hi_less_mi = items[hi] < items[mi];
    if (mi_less_lo == lo_less_hi) mem.swap(T, &items[lo], &items[mi]);
    if (lo_less_hi == hi_less_mi) mem.swap(T, &items[hi], &items[mi]);

    const pivot = items[mi];
    var i = lo;
    var j = hi;

    while (true) {
        // traverse as far as possible
        while (items[i] < pivot) : (i += 1) {}
        while (items[j] > pivot) : (j -= 1) {}

        if (i >= j) return i;

        mem.swap(T, &items[i], &items[j]); // swap elements to correct side of `pivot`
        i += 1;
        j -= 1;
    }
}

const expectEqual = std.testing.expectEqual;
const sort = quickSort;

test "empty array" {
    const arr: []u8 = &.{};
    sort(u8, arr, 0, 0);
    try expectEqual(arr.len, 0);
}

test "array with one element" {
    var arr: [1]u8 = .{4};
    sort(u8, &arr, 0, arr.len - 1);
    try expectEqual(arr[0], 4);
}

test "sorted array" {
    var arr: [10]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    sort(u8, &arr, 0, arr.len - 1);
    for (arr, 1..) |e, i| {
        try expectEqual(e, i);
    }
}

test "reverse order" {
    var arr: [10]u8 = .{ 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };
    sort(u8, &arr, 0, arr.len - 1);
    for (arr, 1..) |e, i| {
        try expectEqual(e, i);
    }
}

test "unsorted array" {
    var arr: [5]u8 = .{ 5, 3, 4, 1, 2 };
    sort(u8, &arr, 0, arr.len - 1);
    for (arr, 1..) |e, i| {
        try expectEqual(e, i);
    }
}
