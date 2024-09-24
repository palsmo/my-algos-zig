// Author: palsmo

const std = @import("std");

const config = @import("build_config.zig");

const Allocator = std.mem.Allocator;
const Entry = config.Entry;
const ModuleCache = std.StringHashMap(*std.Build.Module);
const manifest = config.manifest;

var modcache: ModuleCache = undefined;

const test_targets = [_]std.Target.Query{
    .{}, // native
};

const step = struct {
    var tst: *std.Build.Step = undefined;
};

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    _ = target;
    _ = optimize;

    step.tst = b.step("test", "Run test blocks");

    const op_source = b.option([]const u8, "source", "Source to operate on");

    modcache = ModuleCache.init(allocator);

    for (manifest.entries) |entry| {
        var onetrickpony = false;
        if (op_source) |str| {
            if (!std.mem.eql(u8, entry.name, str)) continue else onetrickpony = true;
        }

        for (entry.make) |make| switch (make) {
            .mod => {}, // TODO: implement
            .run => {}, // TODO: implement
            .tst => try instateTesting(b, &entry),
        };

        if (onetrickpony) break;
    }
}

fn instateTesting(b: *std.Build, entry: *const Entry) !void {
    const optimize: std.builtin.OptimizeMode = .Debug;

    // TODO: should have it's own module cache, since modules may be for different targets,
    // single cache will interfere

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
        tst_obj.root_module.addImport("project", prj_mod);

        if (entry.deps.len != 0) try linkDeps(b, &(tst_obj.root_module), entry.deps, r_target, optimize);

        const tst_run = b.addRunArtifact(tst_obj);
        step.tst.dependOn(&tst_run.step);
    }
}

fn linkDeps(
    b: *std.Build,
    parent: *std.Build.Module,
    deps: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
