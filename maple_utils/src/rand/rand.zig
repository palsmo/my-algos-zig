const rand_array = @import("./rand_array.zig");

// exports -->

pub const RandomArray = rand_array.RandomArray;

// testing -->

test {
    _ = rand_array;
}
