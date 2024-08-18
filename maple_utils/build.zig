//! Author: palsmo
//! Status: Done
//! About: Maple Utils Build Script

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

    // public modules -->

    const mod_pub_root = b.addModule("root", .{
        .root_source_file = b.path("./root.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = mod_pub_root;

    // testing -->

    if (op_file_path) |path| {
        const name = std.fs.path.basename(path);

        const test_compile = b.addTest(.{
            .name = name,
            .root_source_file = b.path("./root.zig"),
            .target = target,
            .optimize = optimize,
        });

        const test_artifact = b.addRunArtifact(test_compile);
        test_step.dependOn(&test_artifact.step);
    }
}
