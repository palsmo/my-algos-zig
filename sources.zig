//! Author: palsmo
//! Status: In Progress
//! About: This file is imported and analyzed by 'build.zig'.

pub const Make = enum {
    exe, // ready executable
    lib, // ready library
    mod, // ready public module
    run, // ready runnable
    tst, // ready tests
};

pub const Source = struct {
    name: []const u8, // reference to 'this' that can be used by another `Source`
    path: []const u8, // relative project to a .zig-file (exclude './' prefix)
    deps: []const []const u8, // depend on other `Source`s (* not their library)
    make: []const Make, // what to make of the source in the build process
};

/// Configure project sources.
pub const sources = [_]Source{.{
    .{
        .name = "bamboo_structs",
        .path = "bamboo_structs/root.zig",
        .deps = &.{
            "maple_utils",
        },
        .make = &.{ .mod, .tst },
    },
    .{
        .name = "maple_utils",
        .path = "maple_utils/root.zig",
        .deps = &.{},
        .make = &.{ .mod, .tst },
    },
}};
