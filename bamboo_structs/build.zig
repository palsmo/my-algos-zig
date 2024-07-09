const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // steps
    const test_step = b.step("test", "Run test-blocks");

    // options -->

    const op_file_name = "file";
    const op_file_desc = "Filepath relative package root";
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

    mod_pub_root.addImport("maple_utils", dep_maple_utils);

    // testing -->

    if (op_file_path) |path| {
        const name = std.fs.path.basename(path);

        const test_file = b.addTest(.{
            .name = name,
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });

        test_file.root_module.addImport("maple_utils", dep_maple_utils);

        const test_file_run = b.addRunArtifact(test_file);
        test_step.dependOn(&test_file_run.step);
    }
}
