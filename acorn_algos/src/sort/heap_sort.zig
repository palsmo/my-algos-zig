const std = @import("std");

pub fn sort(comptime T: type, items: []T) void {
    // build max heap
    var i: usize = items.len / 2;
    while (i > 0) {
        i -= 1;
        siftDown(T, items, i, items.len);
    }

    // heap sort
    var end = items.len;
    while (end > 1) {
        end -= 1;
        std.mem.swap(T, &items[0], &items[end]);
        siftDown(T, items, 0, end);
    }
}

fn siftDown(comptime T: type, items: []T, start: usize, end: usize) void {
    var root = start;
    while (root * 2 + 1 < end) {
        var child = root * 2 + 1;
        if (child + 1 < end and items[child] < items[child + 1]) {
            child += 1;
        }
        if (items[root] < items[child]) {
            std.mem.swap(T, &items[root], &items[child]);
            root = child;
        } else {
            return;
        }
    }
}
