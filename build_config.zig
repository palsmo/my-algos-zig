//! Author: palsmo
//! Status: In Progress
//! Brief: This file is imported and analyzed by 'build.zig'.

const std = @import("std");

pub const manifest = Manifest.init(&entries);
const entries = [_]Entry{
    .{
        .name = "bamboo_structs",
        .path = "./bamboo_structs/root.zig",
        .deps = &.{
            "maple_utils",
        },
        .make = &.{ .mod, .tst },
    },
    .{
        .name = "maple_utils",
        .path = "./maple_utils/root.zig",
        .deps = &.{},
        .make = &.{ .mod, .tst },
    },
};

///  fields |
/// --------|---------------------------------------------------------------------------------------
/// mod     | ...
/// run     | ...
/// tst     | ...
/// ------------------------------------------------------------------------------------------------
pub const Make = enum {
    mod,
    run,
    tst,
};

///  field |
/// -------|----------------------------------------------------------------------------------------
/// name   | Name used as reference to `Source` and as module name.
/// path   | Path relative project to a .zig file (typically 'root.zig').
/// deps   | Depend on other `Source` instances.
/// make   | What to make of the source in the build process.
/// ------------------------------------------------------------------------------------------------
pub const Entry = struct {
    path: []const u8,
    name: []const u8,
    deps: []const []const u8,
    make: []const Make,
};

pub const Manifest = struct {
    entries: []const Entry,
    fn init(_entries: []const Entry) Manifest {
        return .{ .entries = _entries };
    }
    pub fn get(self: *const Manifest, name: []const u8) ?Entry {
        for (self.entries) |entry| if (std.mem.eql(u8, name, entry.name)) return entry;
        return null;
    }
};
