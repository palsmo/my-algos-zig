const bub = @import("./bubble_sort.zig");
const ins = @import("./insertion_sort.zig");
const qui = @import("./quick_sort.zig");

const insertion_n = insertion.sort_n;

// exports -->

pub const bubble = bub.sort;
pub const insertion = ins.sort;
pub const quick = qui.sort;

pub const Options = struct {
    insert_cutoff: u64 = 100, // use insertion sort up to 'this' value
    quick_cutoff: u64 = 1_000_000, // use quick sort up to 'this' value
};

/// Unstable, in-place, best case O(n), average and worst case O(n log n).
/// Uses 'insertion sort' -> 'quick sort' -> 'heap sort', cutoff-values
/// can be overwritten in `options`.
pub fn sort(items: anytype, options: Options) void {
    const len = items.len;

    const i_cutoff = options.insert_cutoff;
    const q_cutoff = options.quick_cutoff;

    switch (len) {
        0...i_cutoff => @call(.always_inline, insertion, .{items}),
        i_cutoff + 1...q_cutoff => @call(.always_inline, quick, .{items}),
        else => {},
    }
}

/// Sorts the first `n` items in `items`.
/// Uses 'insertion sort' under the hood (aware low efficiency on big arrays).
pub fn sort_n(n: usize, items: anytype) void {
    @call(.always_inline, insertion_n, .{ n, items });
}

// testing -->

test {
    _ = bub;
    _ = ins;
    _ = qui;
}
