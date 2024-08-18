//! Author: palsmo
//! Status: Done
//! About: Green Graphics Build Script

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // steps
    const test_step = b.step("test", "Run file test-blocks");

    // options -->

    const op_file_name = "file";
    const op_file_desc = "Filepath relative module root";
    const op_file_path = b.option([]const u8, op_file_name, op_file_desc);

    // dependencies -->

    const dep_maple_utils = b.dependency("maple_utils", .{
        .target = target,
        .optimize = optimize,
    }).module("root");

    // public modules -->

    const mod_pub_root = b.addModule("root", .{
        .root_source_file = b.path("./root.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod_pub_root.link_libc = true;
    mod_pub_root.linkSystemLibrary("X11", .{});
    mod_pub_root.addImport("maple_utils", dep_maple_utils);

    // testing -->

    if (op_file_path) |path| {
        const name = std.fs.path.basename(path);

        const test_compile = b.addTest(.{
            .name = name,
            .root_source_file = b.path("./root.zig"),
            .target = target,
            .optimize = optimize,
        });

        test_compile.root_module.link_libc = true;
        test_compile.root_module.linkSystemLibrary("X11", .{});
        test_compile.root_module.addImport("maple_utils", dep_maple_utils);

        const test_artifact = b.addRunArtifact(test_compile);
        test_step.dependOn(&test_artifact.step);
    }
}
