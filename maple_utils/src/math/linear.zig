//! Author: palsmo
//! Status: In Progress
//! About: Linear Algebra Functionality

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_debug = @import("../debug/root.zig");
const root_float = @import("./float.zig");
const root_int = @import("./int.zig");

const ExecMode = prj.modes.ExecMode;
const ValueError = prj.errors.ValueError;
const assertAndMsg = mod_assert.assertAndMsg;
const assertComptime = mod_assert.assertComptime;
const assertType = mod_assert.assertType;
const assertTypeSame = mod_assert.assertTypeSame;
const checkedAdd = root_int.checkedAdd;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;
const isFinite = root_float.isFinite;
const panic = std.debug.panic;

/// Returns the dot-product of `vec_a` o `vec_b`.
/// Asserts `vec_a` and `vec_b` to be the same *numeric vector* type.
/// Compute - *very cheap*, few basic operations.
/// Issue key specs:
/// - Throws error when calculation overflows (only *.Safe* `exec_mode`).
pub inline fn dot(vec_a: anytype, vec_b: anytype, comptime exec_mode: ExecMode) switch (exec_mode) {
    .uncheck => @TypeOf(vec_a[0]),
    .safe => !@TypeOf(vec_a[0]),
} {
    comptime assertTypeSame(@TypeOf(vec_a), @TypeOf(vec_b));
    comptime assertType(@TypeOf(vec_a).vector.child, .{ .int, .float, .comptime_int, .comptime_float });
    comptime assertType(@TypeOf(vec_a), .{.vector});

    const T_vec = @TypeOf(vec_a);
    const T_vec_info = @typeInfo(T_vec).vector;
    const T_vec_child = T_vec_info.child;

    switch (exec_mode) { // * comptime branch prune
        .uncheck => {
            @setFloatMode(.optimized);
            return @reduce(.Add, vec_a *% vec_b);
        },
        .safe => {
            switch (@typeInfo(T_vec_child)) { // * comptime branch prune
                .int => {
                    const vec_zero: T_vec = @splat(0);
                    if (vec_a == vec_zero or vec_b == vec_zero) return 0;

                    const vec_prod = vec_a *% vec_b;
                    if ((vec_prod / vec_a) != vec_b) return ValueError.overflow; // * mul wraps, div don't

                    var sum: T_vec_child = 0;
                    for (0..T_vec_info.len) |i| {
                        sum = try checkedAdd(T_vec_child, sum, vec_prod[i]);
                    }

                    return sum;
                },
                .float => {
                    const sum = @reduce(.Add, vec_a * vec_b);
                    if (!isFinite(sum, .positive)) return ValueError.overflow;
                    return sum;
                },
                .comptime_int, .comptime_float => {
                    const sum = @reduce(.Add, vec_a *% vec_b);
                    return sum;
                },
                else => unreachable,
            }
        },
    }
}

test dot {
    inline for ([_]type{ u8, i8, f16, comptime_int, comptime_float }) |T| {
        const V = @Vector(3, T);
        const vec_a: V = .{ 1, 2, 3 };
        const vec_b: V = .{ 3, 2, 1 };
        try expectEqual(10, dot(vec_a, vec_b, .Safe));
    }
}

/// Returns the cross-product between `vec_a` x `vec_b`.
/// Asserts `vec_a` and `vec_b` to be the same *numeric vector* type.
/// Compute - *cheap*.
pub inline fn cross(vec_a: anytype, vec_b: anytype) @TypeOf(vec_a) {
    comptime assertTypeSame(@TypeOf(vec_a), @TypeOf(vec_b));
    comptime assertType(@TypeOf(vec_a).vector.child, .{ .int, .float, .comptime_int, .comptime_float });
    comptime assertType(@TypeOf(vec_a), .{.vector});

    return .{
        vec_a[1] * vec_b[2] - vec_a[2] * vec_b[1],
        vec_a[2] * vec_b[0] - vec_a[0] * vec_b[2],
        vec_a[0] * vec_b[1] - vec_a[1] * vec_b[0],
    };
}

test cross {}

///// Calculate the cross product between `vec_a` and `vec_b`.
///// Asserts `vec_a` and `vec_b` to be vector types.
///// Compute - cheap
//pub inline fn cross(vec_a: anytype, vec_b: anytype) @TypeOf(vec_a) {
//    comptime assertVectors(@TypeOf(vec_a), @TypeOf(vec_b));
//
//    return .{
//        vec_a[1] * vec_b[2] - vec_a[2] * vec_b[1],
//        vec_a[2] * vec_b[0] - vec_a[0] * vec_b[2],
//        vec_a[0] * vec_b[1] - vec_a[1] * vec_b[0],
//    };
//}
//
//test cross {}

///// Normalize vector `vec`.
///// Asserts `vec` to be a vector.
///// Compute - moderate
//pub inline fn norm(vec: anytype, comptime exec_mode: ExecMode) @TypeOf(vec) {
//    comptime assertType(@TypeOf(vec), .{.Vector}, @src().fn_name ++ ".vec");
//    return vec / @as(@TypeOf(vec), @splat(length(vec, exec_mode)));
//}
//
//test norm {
//    const V = @Vector(3, f32);
//    const v: V = .{ 3, 4, 0 };
//    const result: V = norm(v, .Safe);
//    const expect: V = .{ 0.6, 0.8, 0 };
//
//    try expectEqual(expect[0], result[0]);
//    try expectEqual(expect[1], result[1]);
//    try expectEqual(expect[2], result[2]);
//}

///// Get the length of vector `vec`.
///// Asserts `vec` to be a vector.
///// Compute - moderate
//pub inline fn length(vec: anytype, comptime exec_mode: ExecMode) f32 {
//    comptime assertType(@TypeOf(vec), .{.Vector}, @src().fn_name ++ ".vec");
//    return @sqrt(dot(vec, vec, exec_mode));
//}
//
//test length {
//    const V = @Vector(3, u8);
//    const vec: V = .{ 1, 2, 2 };
//    try expectEqual(3.0, length(vec, .Safe));
//}
