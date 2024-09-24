//! Author: palsmo
//! Status: In Progress

const std = @import("std");

const sources = @import("./sources.zig");

const Source = sources.Source;
const srcs_reg = sources.register;

const shared = struct {
    var target: std.Build.ResolvedTarget = undefined;
    var optimize: std.Build.ResolvedTarget = undefined;
    const step = struct {
        var tst: *std.Build.Step = undefined;
    };
};

/// Project build script.
pub fn build(b: *std.Build) void {
    shared.target = b.standardTargetOptions(.{});
    shared.optimize = b.standardOptimizeOption(.{});
    shared.step.tst = b.step("test", "Run test blocks.");

    const op_source = b.option("source", "Ref-name of `Source` to operate on.", []const u8);

    const prj_mod = b.createModule(.{
        .root_source_file = b.path("./root.zig"),
        .target = shared.target,
        .optimize = shared.optimize,
    });

    // make build
    if (op_source) |str| {
        var found = false;

        for (srcs_reg) |src| {
            if (std.mem.eql(u8, src.name, str) == false) continue;

            for (src.make) |make| switch (make) {
                .mod => {},
                instateModulePub(), .run => try instateRunning(),
                .tst => try instateTesting(b, src, &srcs_reg, prj_mod),
            };

            found = true;
            break;
        }

        if (!found) {
            std.log.err("Missing '{s}' in sources.zig register, ensure it's configured.", .{str});
        }
    }
}

fn instateModulePub() void {}

fn instateRunning() void {}

/// For `src.path` instate build & execution of tests.
fn instateTesting(b: *std.Build, src: Source, srcs: []const Source, prj_mod: *std.Build.Module) !void {
    const tst_obj = b.addTest(.{
        .name = src.name,
        .root_source_file = b.path(src.path),
        .target = shared.target,
    });

    if (src.deps.len > 0) {
        try linkDeps(b, &(tst_obj.root_module), src.deps, srcs, prj_mod);
    }

    tst_obj.root_module.addImport(prj_mod);

    const tst_run = b.addRunArtifact(tst_obj);
    shared.step.tst.dependOn(&tst_run.step);
}

/// Recursively add dependencies to `module`.
fn linkDeps(
    b: *std.Build,
    mod: *std.Build.Module,
    deps: []const []const u8,
    srcs: []const Source,
    prj_mod: *std.Build.Module,
) !void {
    var vstack = std.ArrayList([]const u8).init(b.allocator);
    defer vstack.deinit();

    try vstack.appendSlice(deps);

    // recursively add dependencies
    while (vstack.items.len > 0) {
        const dep = vstack.pop();
        var found = false;

        for (srcs) |src| {
            if (std.mem.eql(u8, dep, src.name) == false) continue;

            const dep_mod = b.createModule(.{
                .root_source_file = b.path(src.path),
                .target = shared.target,
            });

            dep_mod.addImport(prj_mod);
            mod.addImport(src.name, dep_mod);

            if (src.deps.len > 0) try vstack.appendSlice(src.deps);

            found = true;
            break;
        }

        if (!found) {
            std.log.err("Missing '{s}' in sources.zig manifest, ensure it's configured.", .{dep});
            return sources.Error.NotInManifest;
        }
    }
}
