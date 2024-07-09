//! Read about:
//! https://en.wikipedia.org/wiki/Quicksort

const std = @import("std");
const math = std.math;
const mem = std.mem;

const maple = @import("maple_utils");
const bamboo = @import("bamboo_structs");

const Allocator = std.mem.Allocator;
const RandomArray = maple.RandomArray;
const VStack = bamboo.stack.ByteStack;
const assert = std.debug.assert;
const swap = maple.mem.swap;

/// Sort items of type `T`.
/// Most efficient for medium (>100 items) to large data sets (<10_000_000 items).
/// Less efficient for substantially sorted sets, by default 'median-of-three' pivot
/// selection is used which brings worst-case close to O(n log n) time.
/// Properties:
/// Unstable, in-place, time-complexity best O(n), average O(n log n) and worst case ~O(n^2).
/// Memory consumption is O(n) during and O(1) post.
pub fn QuickSort(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // pivot selection (select pivot and returns it)
            pivot: *const fn (comptime T: type, items: []T, lo: usize, hi: usize, mi: usize) usize,
            // partition scheme (sorts relative pivot, returns pivot's final index)
            scheme: *const fn (comptime T: type, items: []T, lo: usize, hi: usize, pi: usize) usize,
            // namespace containing:
            // eql: inline fn(T: type, a: T, b: T) bool
            comptime ctx: type = struct {
                inline fn eql(T: type, a: T, b: T) bool {
                    return a == b;
                }
            },
        };

        /// The sorting algorithm, inlined with fastest implementation.
        pub fn sort(items: []T) void {
            @call(.always_inline, sortRecursive, .{ T, items });
        }

        /// The sorting algorithm implemented with recursion, works comptime.
        pub fn sortRecursive(items: []T, options: Options,) void {
            comptime verifyContext(options.ctx);
            if (items.len <= 1) return;
            driveRecursive(T, items, 0, items.len -| 1);
        }

        /// The sorting algorithm implemented with iteration (virtual stack).
        pub fn sortIterative(items: []T, allocator: Allocator) !void {
            if (items.len <= 1) return;

            const entries = items.len * 2; // worst-case "recursion depth O(n), 2 values per sequence
            const bytes = (entries * @bitSizeOf(usize) / (8 - 1)) + 1;
            var vstack = try VStack.init(bytes, .{}, allocator);
            defer vstack.deinit();

            try driveIterative(T, items, &vstack);
        }

        // TODO:
        // pub fn sort_parallel(...

        /// Drivetrain for the sorting algorithm - recursive approach.
        fn driveRecursive(items: []T, lo: usize, hi: usize) void {
            if (lo < hi) {
                const p = partition(T, items, lo, hi);
                driveRecursive(T, items, lo, @min(p, p -% 1));
                driveRecursive(T, items, p + 1, hi);
            }
        }

        /// Drivetrain for the sorting algorithm - iterative approach.
        inline fn driveIterative(items: []T, vstack: *VStack) !void {
            try vstack.push(@as(usize, 0)); // lo
            try vstack.push(@as(usize, items.len - 1)); // hi

            while (!vstack.isEmpty()) {
                const hi = try vstack.pop(usize);
                const lo = try vstack.pop(usize);

                //std.debug.print("{any}, {any}, {}, {}", .{ items, items[lo .. hi + 1], lo, hi });
                const p = @call(.always_inline, partition, .{ T, items, lo, hi });
                //std.debug.print(" -> {}, {any}\n", .{ p, items });

                if (p - 1 > lo) {
                    // there's > 1 elements left of pivot
                    try vstack.push(lo);
                    try vstack.push(p - 1);
                }

                if (p + 1 < hi) {
                    // there's > 1 elements right of pivot
                    try vstack.push(p + 1);
                    try vstack.push(hi);
                }
            }
        }

        /// The partition routine for the quick sort algorithm.
        fn partition(items: []T, lo: usize, hi: usize) usize {
            if (hi - lo > 1) {
                const mi: usize = lo + (hi - lo) / 2; // * of measure
                const pi = pivots.medianThreeIdx(T, items, lo, hi, mi);
                return schemes.lomutos(T, items, lo, hi, pi);
                //return scheme.hoares(T, items, p, lo, hi);
            } else {
                if (items[lo] > items[hi]) {
                    swap(T, &items[lo], &items[hi]);
                }
                return lo;
            }
        }
    };
}

/// Partition schemes.
/// An efficient scheme has few comparisons, few swaps, simple branches and
/// linear memory access pattern.
const schemes = struct {
    const Fn = fn comptime T: type, items: []T, lo: usize, hi: usize, pi: usize) usize,

    /// Lomuto's scheme, simpler and efficient scheme.
    /// Sorts `items[lo..hi+1]` relative pivot, returns pivot's final index.
    /// Indexes `pi`, `lo`, `hi` points to the pivot, start and end of the partition.
    pub inline fn lomutos(comptime T: type, items: []T, lo: usize, hi: usize, pi: usize) usize {
        swap(T, &items[pi], &items[hi]);
        const p = items[hi];
        var i = lo;
        for (lo..hi) |j| {
            if (items[j] <= p) {
                swap(T, &items[i], &items[j]);
                i += 1;
            }
        }
        swap(T, &items[i], &items[hi]);
        return i;
    }

    // Hoare's scheme, typically most efficient.
    // Sorts `items[lo..hi+1]` relative pivot, returns pivot's final index.
    // Indexes `pi`, `lo`, `hi` points to the pivot, start and end of the partition.
    //pub inline fn hoares(comptime T: type, items: []T, pi: usize, lo: usize, hi: usize) usize {
    //    var i = lo;
    //    var j = hi;

    //    //while (i < j) {
    //    //    while (i < hi) : (i += 1) {
    //    //        if (items[i] < p)
    //    //    }
    //    //}

    //    while (i < j) {
    //        // move left pointer to the right
    //        while (i < j and items[i] < p) {
    //            i += 1;
    //        }
    //        // move right pointer to the left
    //        while (i < j and items[j] > p) {
    //            j -= 1;
    //        }
    //        if (i < j) {
    //            swap(T, &items[i], &items[j]);
    //            i += 1;
    //            j -= 1;
    //        }
    //    }

    //    return j;
    //}

};

/// Pivot selection methods.
/// A balanced pivot results in the best performance, especially on already
/// sorted arrays that would otherwise be O(n^2) time complexity.
const pivots = struct {
    /// Finds the index among `lo`, `hi` and `mi` which points to the median value.
    /// Uses 'median-xor' logic for fast evaluation.
    pub inline fn medianThreeIdx(comptime T: type, items: []T, lo: usize, hi: usize, mi: usize) usize {
        // is 'x' greater than exclusively one of the others?
        if ((items[lo] > items[hi]) != (items[lo] > items[mi])) return lo;
        if ((items[hi] > items[lo]) != (items[hi] > items[mi])) return hi;
        return mi;
    }

    test medianThreeIdx {
        const T = u8;
        const C = struct { usize, [3]T }; // median-index, items

        const test_cases = [_]C{
            .{ 1, .{ 1, 2, 3 } },
            .{ 2, .{ 1, 3, 2 } },
            .{ 0, .{ 2, 1, 3 } },
            .{ 0, .{ 2, 3, 1 } },
            .{ 2, .{ 3, 1, 2 } },
            .{ 1, .{ 3, 2, 1 } },
        };

        for (test_cases) |case| {
            const index, var items = case;
            const lo: usize = 0;
            const hi: usize = items.len - 1;
            const mi: usize = lo + (hi - lo) / 2; // * of measure
            const i = medianThreeIdx(T, &items, lo, hi, mi);
            try expectEqual(index, i);
        }
    }
};

// testing -->

const testing = @import("./testing.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test pivots {
    _ = pivots;
}

//test QuickSort {
//    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//    defer arena.deinit();
//
//    try testing.sort_array_empty(sort, .{});
//    try testing.sort_array_single(sort, .{});
//    try testing.sort_array_same(sort, .{});
//    try testing.sort_array_sorted(sort, .{});
//    try testing.sort_array_reverse(sort, .{});
//    try testing.sort_array_unsorted(sort, .{});
//    try testing.sort_array_unsorted(sortRecursive, .{});
//    try testing.sort_array_unsorted(sortIterative, .{arena.allocator()});
//    comptime testing.sort_array_unsorted(sortRecursive, .{}) catch unreachable;
//}
//
//// performance -->
//
//const time = std.time;
//
//pub fn perform_sort_iterative(comptime T: type, items: []T, allocator: Allocator) !u64 {
//    var timer = try time.Timer.start();
//    try sortIterative(T, items, allocator);
//    return timer.read();
//}
//
//pub fn perform_sort_recursive(comptime T: type, items: []T) !u64 {
//    var timer = try time.Timer.start();
//    sortRecursive(T, items);
//    return timer.read();
//}
//
//fn performSort(
//    comptime T: type,
//    items: []T,
//    sort_fn: anytype,
//    args: anytype,
//    allocator: Allocator,
//) !u64 {
//    // warmup
//    const warmup_items = try allocator.dupe(T, items);
//    try testing.call_sort(T, sort_fn, warmup_items, args);
//
//    // timed run
//    const perform_items = try allocator.dupe(T, items);
//    var timer = try time.Timer.start();
//    try testing.call_sort(T, sort_fn, perform_items, args);
//    return timer.read();
//}
//
//pub fn main() !void {
//    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//    defer arena.deinit();
//    const allocator = arena.allocator();
//
//    const n_items = 500_000;
//    const T = u32;
//
//    const n_runs = 20;
//    var recursive_times: [n_runs]u64 = undefined;
//    var iterative_times: [n_runs]u64 = undefined;
//
//    for (0..n_runs) |i| {
//        const items = try RandomArray.get(n_items, T, allocator);
//        recursive_times[i] = try performSort(T, items, sortRecursive, .{}, allocator);
//        iterative_times[i] = try performSort(T, items, sortIterative, .{allocator}, allocator);
//    }
//
//    const best_recursive = std.mem.min(u64, &recursive_times);
//    const best_iterative = std.mem.min(u64, &iterative_times);
//    const wrst_recursive = std.mem.max(u64, &recursive_times);
//    const wrst_iterative = std.mem.max(u64, &iterative_times);
//
//    const fmt_best = "Best time sorting ({s}) {} items: {}\n";
//    std.debug.print(fmt_best, .{ "recursively", n_items, std.fmt.fmtDuration(best_recursive) });
//    std.debug.print(fmt_best, .{ "iteratively", n_items, std.fmt.fmtDuration(best_iterative) });
//
//    const fmt_wrst = "Worst time sorting ({s}) {} items: {}\n";
//    std.debug.print(fmt_wrst, .{ "recursively", n_items, std.fmt.fmtDuration(wrst_recursive) });
//    std.debug.print(fmt_wrst, .{ "iteratively", n_items, std.fmt.fmtDuration(wrst_iterative) });
//}
