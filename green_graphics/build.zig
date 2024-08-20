//! Author: palsmo
//! Status: Done
//! About: Green Graphics Build Script

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run file test-blocks");

    // options -->

    const op_file_name = "file";
    const op_file_desc = "Filepath relative module root";
    const op_file_path = b.option([]const u8, op_file_name, op_file_desc);

    // dependencies -->

    // maple
    const dep_mapleutils = b.dependency("maple_utils", .{
        .target = target,
        .optimize = optimize,
    }).module("root");

    // public modules -->

    // root
    const mod_pub_root = b.addModule("root", .{
        .root_source_file = b.path("./root.zig"),
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    mod_pub_root.addImport("maple_utils", dep_mapleutils);
    mod_pub_root.linkSystemLibrary("xcb", .{ .preferred_link_mode = .static });

    // testing -->

    if (op_file_path) |path| {
        const name = std.fs.path.basename(path);

        const test_compile = b.addTest(.{
            .name = name,
            .root_source_file = b.path("./root.zig"),
            .link_libc = true,
            .target = target,
            .optimize = optimize,
        });

        test_compile.root_module.addImport("maple_utils", dep_mapleutils);
        test_compile.root_module.linkSystemLibrary("xcb", .{ .preferred_link_mode = .static });

        const test_artifact = b.addRunArtifact(test_compile);
        test_step.dependOn(&test_artifact.step);
    }
}
