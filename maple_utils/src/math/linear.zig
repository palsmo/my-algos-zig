//! Author: palsmo
//! Status: In Progress
//! About: Linear Algebra Library

const std = @import("std");
const math = std.math;

const maple_debug = @import("../debug/root.zig");
const maple_typ = @import("../typ/root.zig");

const assertAndMsg = maple_debug.assertAndMsg;
const assertComptime = maple_debug.assertComptime;
const assertType = maple_typ.assertType;
const expectEqual = std.testing.expectEqual;
const comptimePrint = std.fmt.comptimePrint;
const panic = std.debug.panic;

/// Float vectors with 32-bit precision.
/// Modern GPU's are optimized for floating-point operations, particularly f32.
pub const fVec2 = @Vector(2, f32);
pub const fVec3 = @Vector(3, f32);
pub const fVec4 = @Vector(4, f32);
/// Unsigned integer vectors with 64-bit precision.
pub const uVec2 = @Vector(2, u64);
pub const uVec3 = @Vector(3, u64);
pub const uVec4 = @Vector(4, u64);
/// Signed integer vectors with 64-bit precision.
pub const iVec2 = @Vector(2, i64);
pub const iVec3 = @Vector(3, i64);
pub const iVec4 = @Vector(4, i64);

/// Configuration for linear algebra operations in this library.
/// _.Fast_ is fastest, _.Safe_ (comes with some overhead) panics on overflows.
///
///  overflow |      factor
/// ----------|-----------------
/// integer   | overflow bit
/// float     | inf bit-pattern
/// ----------------------------
pub const Mode = enum {
    Fast,
    Safe,
};

/// Assert that `T_vec_a` and `T_vec_b` are vectors of same type.
fn assertVectors(comptime T_vec_a: type, comptime T_vec_b: type) void {
    assertComptime(@src().fn_name);
    const msg = "Type mismatch for '{s}' (`vec_a`) and '{s}' (`vec_b`).";
    assertAndMsg(T_vec_a == T_vec_b, msg, .{ @typeName(T_vec_a), @typeName(T_vec_b) });
    assertType(T_vec_a, .{.Vector}, @src().fn_name ++ ".T_vec_a");
}

/// Calculate the dot product of vectors `a` and `b`.
/// Depending on `mode` certain logic may be pruned or optimized comptime.
/// Asserts `a` and `b` to be vector types.
/// Computation: very cheap
pub inline fn dot(vec_a: anytype, vec_b: anytype, comptime mode: Mode) @TypeOf(vec_a[0]) {
    comptime assertVectors(@TypeOf(vec_a), @TypeOf(vec_b));

    const T_vec_info = @typeInfo(@TypeOf(vec_a)).Vector;
    var sum: T_vec_info.child = 0;

    switch (mode) {
        .Fast => {
            const vec_prod = vec_a * vec_b;
            inline for (0..T_vec_info.len) |i| {
                sum += vec_prod[i];
            }
        },
        .Safe => {
            switch (@typeInfo(T_vec_info.child)) {
                .Float => {},
                .Int, .ComptimeInt => {
                    const vec_prod, const vec_mul_of = @mulWithOverflow(vec_a, vec_b);
                    var f_overflow = false;

                    inline for (0..T_vec_info.len) |i| {
                        switch (vec_mul_of[i]) {
                            0 => {},
                            1 => f_overflow = true,
                        }
                    }

                    if (!f_overflow) {
                        inline for (0..T_vec_info.len) |i| {
                            const result_add = @addWithOverflow(sum, vec_prod[i]);
                            switch (result_add[1]) {
                                0 => sum += result_add[0],
                                1 => {
                                    f_overflow = true;
                                    break;
                                },
                            }
                        }
                    }

                    if (f_overflow) {
                        if (@inComptime()) {
                            @compileError(comptimePrint(
                                "Overflow occurred in dot product calculation between vectors {any} and {any}.",
                                .{ vec_a, vec_b },
                            ));
                        } else {
                            panic(
                                "Overflow occurred in dot product calculation between vectors {any} and {any}.",
                                .{ vec_a, vec_b },
                            );
                        }
                    }
                },
                .Pointer => {},
                else => unreachable,
            }
        },
    }

    return sum;
}

test dot {
    const vec_a: uVec3 = .{ 1, 2, 3 };
    const vec_b: uVec3 = .{ 3, 2, 1 };
    const result = dot(vec_a, vec_b, .Safe);
    try expectEqual(10, result);
}

/// Calculate the cross product for vectors `a` and `b`.
/// Asserts `a` and `b` to be vector types.
/// Computation: cheap
pub inline fn cross(vec_a: anytype, vec_b: anytype) @TypeOf(vec_a) {
    comptime assertVectors(@TypeOf(vec_a), @TypeOf(vec_b));

    return .{
        vec_a[1] * vec_b[2] - vec_a[2] * vec_b[1],
        vec_a[2] * vec_b[0] - vec_a[0] * vec_b[2],
        vec_a[0] * vec_b[1] - vec_a[1] * vec_b[0],
    };
}

test cross {}

/// Normalize vector `v`.
/// Asserts `v` to be a vector type.
/// Computation | moderate
pub inline fn norm(vec: anytype, comptime mode: Mode) @TypeOf(vec) {
    comptime assertType(@TypeOf(vec), .{.Vector}, @src().fn_name ++ ".vec");
    return vec / @as(@TypeOf(vec), @splat(length(vec, mode)));
}

test norm {
    const v: fVec3 = .{ 3, 4, 0 };
    const n = norm(v, .Safe);
    const expected: fVec3 = .{ 0.6, 0.8, 0 };

    try expectEqual(expected[0], n[0]);
    try expectEqual(expected[1], n[1]);
    try expectEqual(expected[2], n[2]);
}

/// Get the length of vector `v`.
/// Asserts `v` to be a vector type.
/// Computation | moderate
pub inline fn length(vec: anytype, comptime mode: Mode) f32 {
    comptime assertType(@TypeOf(vec), .{.Vector}, @src().fn_name ++ ".vec");
    return @sqrt(dot(vec, vec, mode));
}

test length {
    const v: uVec3 = .{ 1, 2, 2 };
    try expectEqual(3.0, length(v, .Safe));
}
