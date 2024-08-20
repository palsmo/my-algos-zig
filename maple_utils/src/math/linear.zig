//! Author: palsmo
//! Status: In Progress
//! About: Linear Algebra Library

const std = @import("std");
const math = std.math;

const proj_shared = @import("./../../../shared.zig");
const mod_assert = @import("../assert/root.zig");
const mod_debug = @import("../debug/root.zig");
const root_prim = @import("./primitive.zig");
const root_shared = @import("./shared.zig");

const ExecMode = proj_shared.ExecMode;
const ValueError = root_shared.ValueError;
const assertAndMsg = mod_assert.misc.assertAndMsg;
const assertComptime = mod_assert.misc.assertComptime;
const assertType = mod_assert.misc.assertType;
const assertTypeSame = mod_assert.misc.assertTypeSame;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;
const safeAdd = root_prim.safeAdd;
const safeMul = root_prim.safeMul;

/// Calculate the dot-product of `vec_a` o `vec_b`.
/// Asserts `vec_a` and `vec_b` to be numeric vectors of the same type.
/// Compute - very cheap, few basic operations.
/// Issue key specs:
/// - Throw error when calculation overflows (only *.Safe* `exec_mode`).
pub inline fn dot(vec_a: anytype, vec_b: anytype, comptime exec_mode: ExecMode) switch (exec_mode) {
    .Uncheck => @TypeOf(vec_a[0]),
    .Safe => !@TypeOf(vec_a[0]),
} {
    comptime assertTypeSame(vec_a, vec_b);
    comptime assertType(@TypeOf(vec_a), .{.Vector});
    comptime assertType(@typeInfo(@TypeOf(vec_a)).Vector.child, .{ .Int, .Float, .ComptimeInt, .ComptimeFloat });

    const T_vec = @TypeOf(vec_a);
    const T_vec_child = @typeInfo(T_vec).Vector.child;

    switch (exec_mode) { // * comptime branch prune
        .Uncheck => return @reduce(.Add, vec_a *% vec_b),
        .Safe => {
            switch (@typeInfo(T_vec_child)) { // * comptime branch prune
                .Int => {
                    const vec_zero: T_vec = @splat(0);
                    if (vec_a == vec_zero or vec_b == vec_zero) return 0;

                    const vec_prod = vec_a *% vec_b;
                    if ((vec_prod / vec_a) != vec_b) return ValueError.Overflow; // * mul wraps, div don't

                    var sum: T_vec_child = 0;
                    inline for (0..@typeInfo(T_vec).Vector.len) |i| {
                        sum = try safeAdd(T_vec_child, sum, vec_prod[i]);
                    }

                    return sum;
                },
                .Float => {
                    const sum = @reduce(.Add, vec_a * vec_b);
                    if (std.math.isPositiveInf(sum)) return ValueError.Overflow;

                    return sum;
                },
                .ComptimeInt, .ComptimeFloat => return @reduce(.Add, vec_a *% vec_b),
                else => unreachable,
            }
        },
    }
}

test dot {
    const V = @Vector(3, u8);
    const vec_a: V = .{ 1, 2, 3 };
    const vec_b: V = .{ 3, 2, 1 };
    const expect = 10;
    const result = dot(vec_a, vec_b, .Safe);
    try expectEqual(expect, result);
}

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
