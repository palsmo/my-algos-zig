const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        //.{ .cpu_arch = .aarch64, .os_tag = .macos },
        //.{ .cpu_arch = .x86_64, .os_tag = .windows },
    };

    const test_step = b.step("test", "Run tests");

    for (test_targets) |target| {
        const tests = b.addTest(.{
            .root_source_file = b.path("./tests.zig"),
            .target = b.resolveTargetQuery(target),
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
}
