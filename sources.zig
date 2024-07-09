//! This file is imported and analyzed by 'build.zig'.

pub const Make = enum {
    exe, // ready executable
    lib, // ready library
    run, // ready main-function
    tst, // ready tests
};

pub const Source = struct {
    name: []const u8, // reference to 'this' that can be used by another `Source`
    path: []const u8, // relative project to a .zig-file (exclude './' prefix)
    comp: []const Source, // components in 'this', for structuring purpose (names are combined with '_')
    deps: []const []const u8, // depend on other `Source`s (* not their library)
    make: []const Make, // what to make of the source in the build process
};

/// Configure project sources.
pub const sources = [_]Source{ .{
    .name = "stack",
    .path = "struct/stack/root.zig",
    .comp = &.{},
    .deps = &.{},
    .make = &.{.tst},
}, .{
    .name = "utility",
    .path = "utility/root.zig",
    .comp = &.{},
    .deps = &.{},
    .make = &.{.tst},
}, .{
    .name = "sort",
    .path = "sort/root.zig",
    .comp = &.{
        .{
            .name = "quick",
            .path = "sort/quick_sort.zig",
            .comp = &.{},
            .deps = &.{ "stack", "utility" },
            .make = &.{ .tst, .run },
        },
        .{
            .name = "insertion",
            .path = "sort/insertion_sort.zig",
            .comp = &.{},
            .deps = &.{"utility"},
            .make = &.{ .tst, .run },
        },
    },
    .deps = &.{ "stack", "utility" },
    .make = &.{ .lib, .tst },
} };
