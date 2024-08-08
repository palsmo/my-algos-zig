const std = @import("std");

const sources = @import("./sources.zig");

const Allocator = std.mem.Allocator;
const Build = std.Build;
const Source = sources.Source;
const panic = std.debug.panic;

const test_targets = [_]std.Target.Query{
    .{},
    //.{ .cpu_arch = .x86_64, .os_tag = .linux },
    //.{ .cpu_arch = .aarch64, .os_tag = .macos },
    //.{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // init source maps
    const maps = try createSourceMaps(&sources.sources);
}
