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

    // init arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // init source maps
    const maps = try createSourceMaps(&sources.sources, allocator);

    // add option 'algo'
    const op_name = "algo";
    const op_desc = "Filepath to algorithm to 'run' or 'test'";
    const op_path = b.option([]const u8, op_name, op_desc);

    // form steps
    const exe_step = b.step("exe", "Install executable.");
    const lib_step = b.step("lib", "Install library.");
    const run_step = b.step("run", "Run main-function.");
    const tst_step = b.step("test", "Run test blocks.");

    // make build -->

    if (op_path) |path| {
        const _path = std.mem.trimLeft(u8, path, "./");
        if (maps.path_map.get(_path)) |src| {
            for (src.make) |make| {
                switch (make) {
                    .exe => try buildExecutable(b, exe_step, src, maps.name_map, &target, optimize, allocator),
                    .lib => try buildLibrary(b, lib_step, src, maps.name_map, &target, optimize, allocator),
                    .run => try runExecutable(b, run_step, src, maps.name_map, &target, optimize, allocator),
                    .tst => try runTests(b, tst_step, src, maps.name_map, &test_targets, optimize, allocator),
                }
            }
        } else {
            std.log.err("Missing {s} in 'sources.zig', ensure it's configured.", .{path});
        }
    }
}

//const SourceMapType = std.StaticStringMap(*const Source);

//fn createSourceMaps(
//    srcs: []const Source,
//) !struct { path_map: *const SourceMapType, name_map: *const SourceMapType } {
//    if (!@inComptime()) panic("Invalid at runtime.");
//
//    const path_kvp, const name_kvp = blk: {
//        var out: []const T = &.{};
//        out = out ++ &.{
//        break :blk out;
//    };
//
//}

const SourceMapType = std.StringHashMap(*const Source);

fn createSourceMaps(
    srcs: []const Source,
    allocator: Allocator, // ! should be an arena allocator
) !struct { path_map: *const SourceMapType, name_map: *const SourceMapType } {
    // store source maps on heap
    var path_map = try allocator.create(SourceMapType);
    var name_map = try allocator.create(SourceMapType);

    // initialize individual source maps
    path_map.* = SourceMapType.init(allocator);
    name_map.* = SourceMapType.init(allocator);

    // initialize virtual stack
    var vstack = std.ArrayList(struct { prefix: []const u8, sources: []const Source }).init(allocator);
    try vstack.append(.{ .prefix = "", .sources = srcs });

    // recursively flatten `srcs`,
    // * items within `comp` get their name prefixed with parent name
    while (vstack.popOrNull()) |*item| {
        for (item.sources) |*src| {
            const full_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ item.prefix, src.name });

            try path_map.put(src.path, src);
            try name_map.put(full_name, src);

            if (src.comp.len > 0) {
                // for new components store along with prefix
                const new_prefix = try std.fmt.allocPrint(allocator, "{s}_", .{full_name});
                try vstack.append(.{ .prefix = new_prefix, .sources = src.comp });
            }
        }
    }

    return .{ .path_map = path_map, .name_map = name_map };
}

/// Build and install executable binary of 'src'.
fn buildExecutable(
    b: *Build,
    step: *Build.Step,
    src: *const Source,
    name_map: *const SourceMapType,
    target: *const Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    allocator: Allocator, // ! should be an arena allocator
) !void {
    const exe = b.addExecutable(.{
        .name = src.name,
        .root_source_file = b.path(src.path),
        .target = target.*,
        .optimize = optimize,
    });

    if (src.deps.len > 0) {
        try linkDeps(b, &exe.root_module, src.deps, name_map, target, optimize, allocator);
    }

    const exe_install = b.addInstallArtifact(exe, .{});
    step.dependOn(&exe_install.step);
}

/// Build and install library binary of 'src'.
fn buildLibrary(
    b: *Build,
    step: *Build.Step,
    src: *const Source,
    name_map: *const SourceMapType,
    target: *const Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    allocator: Allocator, // ! should be an arena allocator
) !void {
    const lib = b.addStaticLibrary(.{
        .name = src.name,
        .root_source_file = b.path(src.path),
        .target = target.*,
        .optimize = optimize,
    });

    if (src.deps.len > 0) {
        try linkDeps(b, &lib.root_module, src.deps, name_map, target, optimize, allocator);
    }

    const lib_install = b.addInstallArtifact(lib, .{});
    step.dependOn(&lib_install.step);
}

/// Build and run executable binary of 'src'.
fn runExecutable(
    b: *Build,
    step: *Build.Step,
    src: *const Source,
    name_map: *const SourceMapType,
    target: *const Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    allocator: Allocator, // ! should be an arena allocator
) !void {
    const exe = b.addExecutable(.{
        .name = src.name,
        .root_source_file = b.path(src.path),
        .target = target.*,
        .optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast }),
    });

    if (src.deps.len > 0) {
        try linkDeps(b, &exe.root_module, src.deps, name_map, target, optimize, allocator);
    }

    const exe_run = b.addRunArtifact(exe);
    step.dependOn(&exe_run.step);
}

/// Build and run executable binary of 'src'.
fn runTests(
    b: *Build,
    step: *Build.Step,
    src: *const Source,
    name_map: *const SourceMapType,
    targets: []const std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    allocator: Allocator, // ! should be an arena allocator
) !void {
    for (targets) |target| {
        const r_target = b.resolveTargetQuery(target);

        const tst = b.addTest(.{
            .name = src.name,
            .root_source_file = b.path(src.path),
            .target = r_target,
        });

        if (src.deps.len > 0) {
            try linkDeps(b, &tst.root_module, src.deps, name_map, &r_target, optimize, allocator);
        }

        const tst_run = b.addRunArtifact(tst);
        step.dependOn(&tst_run.step);
    }
}

/// Recursively add dependencies to `module`.
fn linkDeps(
    b: *Build,
    module: *Build.Module,
    deps: []const []const u8,
    name_map: *const SourceMapType,
    target: *const Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    allocator: Allocator, // ! should be an arena allocator
) !void {
    // initialize virtual stack
    var vstack = std.ArrayList([]const []const u8).init(allocator);
    try vstack.append(deps);

    // recursively add dependencies
    while (vstack.items.len > 0) {
        for (vstack.pop()) |name| {
            const src = name_map.get(name) orelse {
                std.log.err("Missing {s} in `sources`, ensure it's configured.", .{name});
                return error.SourceNotConfigured;
            };

            const mod = b.createModule(.{
                .root_source_file = b.path(src.path),
                .target = target.*,
                .optimize = optimize,
            });

            module.addImport(src.name, mod);
            if (src.deps.len > 0) try vstack.append(src.deps);
        }
    }
}
