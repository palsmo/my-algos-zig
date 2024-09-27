// Author: palsmo
// Status: In Progress

const std = @import("std");

const config = @import("build_config.zig");

const Allocator = std.mem.Allocator;
const Entry = config.Entry;
const ModuleCache = std.StringHashMap(*std.Build.Module);
const manifest = config.manifest;

const test_targets = [_]std.Target.Query{
    .{}, // native
};

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = target;
    _ = optimize;

    const step_tst = b.step("test", "Run test blocks");

    const op_source = b.option([]const u8, "source", "Source to operate on");

    for (manifest.entries) |entry| {
        var onetrickpony = false;
        if (op_source) |str| {
            if (!std.mem.eql(u8, entry.name, str)) continue else onetrickpony = true;
        }

        for (entry.make) |make| switch (make) {
            .mod => try instatePubModule(),
            .run => try instateRunning(),
            .tst => try instateTesting(b, &entry, step_tst, allocator),
        };

        if (onetrickpony) break;
    }
}

fn instatePubModule() !void {}

fn instateRunning() !void {}

fn instateTesting(b: *std.Build, entry: *const Entry, step: *std.Build.Step, allocator: Allocator) !void {
    const optimize: std.builtin.OptimizeMode = .Debug;
    var modcache = ModuleCache.init(allocator);

    for (test_targets) |target| {
        const r_target = b.resolveTargetQuery(target);

        const tst_obj = b.addTest(.{
            .name = entry.name,
            .root_source_file = b.path(entry.path),
            .target = r_target,
            .optimize = optimize,
        });

        const prj_mod = b.createModule(.{
            .root_source_file = b.path("./root.zig"),
            .target = r_target,
            .optimize = optimize,
        });

        try modcache.put("project", prj_mod);
        var tst_mod = tst_obj.root_module;
        tst_mod.addImport("project", prj_mod);

        if (entry.deps.len != 0) try linkDeps(b, &tst_mod, entry.deps, r_target, optimize, &modcache);

        const tst_run = b.addRunArtifact(tst_obj);
        step.dependOn(&tst_run.step);
    }
}

fn linkDeps(
    b: *std.Build,
    parent: *std.Build.Module,
    deps: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modcache: *ModuleCache,
) !void {
    var vstack = std.ArrayList([]const u8).init(b.allocator);
    defer vstack.deinit();

    try vstack.appendSlice(deps);

    while (vstack.popOrNull()) |dep| {
        const dep_entry: Entry = manifest.get(dep) orelse {
            std.log.err("Missing '{s}' in sources.zig manifest, ensure it's configured.", .{dep});
            continue;
        };
        const dep_mod = modcache.get(dep_entry.name) orelse blk: {
            break :blk b.createModule(.{
                .root_source_file = b.path(dep_entry.path),
                .target = target,
                .optimize = optimize,
            });
        };

        dep_mod.addImport("project", modcache.get("project") orelse unreachable);
        parent.addImport(dep_entry.name, dep_mod);

        try modcache.put(dep_entry.name, dep_mod);
        if (dep_entry.deps.len != 0) try vstack.appendSlice(dep_entry.deps);
    }
}
