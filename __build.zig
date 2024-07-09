const std = @import("std");

const srcs = @import("./sources.zig");

const Allocator = std.mem.Allocator;
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const Source = sources.Source;

const sources = srcs.sources;

const test_targets = [_]std.Target.Query{
    .{},
    //.{ .cpu_arch = .x86_64, .os_tag = .linux },
    //.{ .cpu_arch = .aarch64, .os_tag = .macos },
    //.{ .cpu_arch = .x86_64, .os_tag = .windows },
};

const Option = struct {
    name: []const u8 = "algo",
    desc: []const u8 = "Filepath to 'exe', 'lib', 'run', 'tst'",
    read: type = []const u8,
    fn_ptr: *const fn(...) bool,
    fn_args: *anyopaque,
};

const options = [_]Option{
    .{
        .name = "algo",
        .desc = "Filepath to 'exe', 'lib', 'run', 'tst'",
        .read = []const u8,
        .fn_ptr = std.mem.eql,
        .fn_args = &.{ u8 },
    },
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // init arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // init source maps
    // const maps = try createSourceMaps(&sources.sources, allocator);

    // add option 'algo'
    //const op_algo_name = "algo";
    //const op_algo_desc = "Filepath to algorithm to 'run' or 'test'";
    //const op_algo_path = b.option([]const u8, op_algo_name, op_algo_desc);
    inline for (options) |opt| {
        const b.option(opt.read, opt.name, opt.desc);
    }

    // form steps
    const exe_step = b.step("exe", "Build executable.");
    //const lib_step = b.step("lib", "Build library.");
    //const run_step = b.step("run", "Run executable.");
    //const tst_step = b.step("test", "Run test blocks.");

    inline for (sources) |*src| {
        for (options) |opt| {

        }
        if (op_algo_path) |path| {
            const _path = std.mem.trimLeft(u8, path, "./");
            if (!std.mem.eql(u8, src.path, _path)) continue;

            std.log.err("Missing {s} in 'sources.zig', ensure it's configured.", .{path});

            for (src.make) |make| {
                switch (make) {
                    .exe => try buildExecutable(b, exe_step, src, &target, optimize),
                    //.lib => try buildLibrary(b),
                    //.run => try runExecutable(b),
                    //.tst => try runTests(b),
                    else => {},
                }
            }
        }
    }
}

const SourceMapType = std.StringHashMap(*const Source);

//fn createSourceMaps(
//    srcs: []const Source,
//    allocator: Allocator, // ! should be an arena allocator
//) !struct { path_map: *const SourceMapType, name_map: *const SourceMapType } {
//    // store source maps on heap
//    var path_map = try allocator.create(SourceMapType);
//    var name_map = try allocator.create(SourceMapType);
//
//    // initialize individual source maps
//    path_map.* = SourceMapType.init(allocator);
//    name_map.* = SourceMapType.init(allocator);
//
//    // initialize virtual stack
//    var vstack = std.ArrayList(struct { prefix: []const u8, sources: []const Source }).init(allocator);
//    try vstack.append(.{ .prefix = "", .sources = srcs });
//
//    // recursively flatten `srcs`,
//    // * items within `comp` get their name prefixed with parent name
//    while (vstack.popOrNull()) |*item| {
//        for (item.sources) |*src| {
//            const full_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ item.prefix, src.name });
//
//            try path_map.put(src.path, src);
//            try name_map.put(full_name, src);
//
//            if (src.comp.len > 0) {
//                // for new components store along with prefix
//                const new_prefix = try std.fmt.allocPrint(allocator, "{s}_", .{full_name});
//                try vstack.append(.{ .prefix = new_prefix, .sources = src.comp });
//            }
//        }
//    }
//
//    return .{ .path_map = path_map, .name_map = name_map };
//}

fn buildExecutable(b: *Build, step: *Build.Step, src: *const Source, target: *const Build.ResolvedTarget, optimize: OptimizeMode,) !void {
    const exe = b.addExecutable(.{
        .name = src.name,
        .root_source_file = b.path(src.path),
        .target = target,
        .optimize = optimize,
    });

    try addDependencies(b, exe, src.deps, target, optimize);

    const exe_install = b.addInstallArtifact(exe, .{});
    step.dependOn(&exe_install.step);
}

fn addDependencies(b: *Build, artifact: *Build.Step.Compile, deps: []const []const u8, target: *Build.ResolvedTarget, optimize: OptimizeMode) !void {
    for (deps) |dep_name| {
        for (sources) |src| {
            if (std.mem.eql(u8, src.name, dep_name)) {
                const module = b.addModule(src.name, .{
                    .source_file = .{ .path = src.path },
                    .dependencies = &.{},
                });
                try artifact.root_module.addImport(src.name, module);
                break;
            }
        }
    }
}

///// Ready executable from `src`.
//fn exeSource(
//    b: *Build,
//    step: *Build.Step,
//    src: *const Source,
//    name_src_map: *const SourceMapType,
//    target: *const Build.ResolvedTarget,
//    optimize: std.builtin.OptimizeMode,
//    allocator: Allocator, // ! should be an arena allocator
//) !void {
//    const exe = b.addExecutable(.{
//        .name = src.name,
//        .root_source_file = b.path(src.path),
//        .target = target.*,
//        .optimize = optimize,
//    });
//
//    if (src.deps.len > 0) {
//        try linkDeps(b, &exe.root_module, src.deps, name_src_map, target, optimize, allocator);
//    }
//
//    const exe_install = b.addInstallArtifact(exe, .{});
//    step.dependOn(&exe_install.step);
//}
//
///// Ready library from `src`.
//fn libSource(
//    b: *Build,
//    step: *Build.Step,
//    src: *const Source,
//    name_src_map: *const SourceMapType,
//    target: *const Build.ResolvedTarget,
//    optimize: std.builtin.OptimizeMode,
//    allocator: Allocator, // ! should be an arena allocator
//) !void {
//    const lib = b.addStaticLibrary(.{
//        .name = src.name,
//        .root_source_file = b.path(src.path),
//        .target = target.*,
//        .optimize = optimize,
//    });
//
//    if (src.deps.len > 0) {
//        try linkDeps(b, &lib.root_module, src.deps, name_src_map, target, optimize, allocator);
//    }
//
//    const lib_install = b.addInstallArtifact(lib, .{});
//    step.dependOn(&lib_install.step);
//}
//
///// Ready run main-function from `src`.
//fn runSource(
//    b: *Build,
//    step: *Build.Step,
//    src: *const Source,
//    name_src_map: *const SourceMapType,
//    target: *const Build.ResolvedTarget,
//    optimize: std.builtin.OptimizeMode,
//    allocator: Allocator, // ! should be an arena allocator
//) !void {
//    const exe = b.addExecutable(.{
//        .name = src.name,
//        .root_source_file = b.path(src.path),
//        .target = target.*,
//        .optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast }),
//    });
//
//    if (src.deps.len > 0) {
//        try linkDeps(b, &exe.root_module, src.deps, name_src_map, target, optimize, allocator);
//    }
//
//    const exe_run = b.addRunArtifact(exe);
//    step.dependOn(&exe_run.step);
//}
//
///// Ready tests from `src`.
//fn tstSource(
//    b: *Build,
//    step: *Build.Step,
//    src: *const Source,
//    name_src_map: *const SourceMapType,
//    targets: []const std.Target.Query,
//    optimize: std.builtin.OptimizeMode,
//    allocator: Allocator, // ! should be an arena allocator
//) !void {
//    for (targets) |target| {
//        const r_target = b.resolveTargetQuery(target);
//
//        const tst = b.addTest(.{
//            .name = src.name,
//            .root_source_file = b.path(src.path),
//            .target = r_target,
//        });
//
//        if (src.deps.len > 0) {
//            try linkDeps(b, &tst.root_module, src.deps, name_src_map, &r_target, optimize, allocator);
//        }
//
//        const tst_run = b.addRunArtifact(tst);
//        step.dependOn(&tst_run.step);
//    }
//}
//
///// Recursively adds dependencies to `module`.
//fn linkDeps(
//    b: *Build,
//    module: *Build.Module,
//    deps: []const []const u8,
//    name_src_map: *const SourceMapType,
//    target: *const Build.ResolvedTarget,
//    optimize: std.builtin.OptimizeMode,
//    allocator: Allocator, // ! should be an arena allocator
//) !void {
//    // initialize virtual stack
//    var vstack = std.ArrayList([]const []const u8).init(allocator);
//    try vstack.append(deps);
//
//    // recursively add dependencies
//    while (vstack.items.len > 0) {
//        for (vstack.pop()) |name| {
//            const src = name_src_map.get(name) orelse {
//                std.log.err("Missing {s} in `sources`, ensure it's configured.", .{name});
//                return error.SourceNotConfigured;
//            };
//
//            const mod = b.createModule(.{
//                .root_source_file = b.path(src.path),
//                .target = target.*,
//                .optimize = optimize,
//            });
//
//            module.addImport(src.name, mod);
//            if (src.deps.len > 0) try vstack.append(src.deps);
//        }
//    }
//}
