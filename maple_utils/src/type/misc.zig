//! Author: palsmo
//! Status: In Progress
//! Brief: ...

const std = @import("std");
const builtin = std.builtin;

const mod_assert = @import("../assert/root.zig");
const mod_math = @import("../math/root.zig");

const Signedness = builtin.Signedness;
const assertComptime = mod_assert.assertComptime;
const assertFn = mod_assert.assertFn;
const assertType = mod_assert.assertType;
const comptimePrint = std.fmt.comptimePrint;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;
const nextPowerOf2 = mod_math.int.nextPowerOf2;

/// Constructs a specific *integer* type.
pub fn TInt(comptime signedness: Signedness, comptime bit_count: u16) type {
    return @Type(.{ .int = .{ .signedness = signedness, .bits = bit_count } });
}

test TInt {
    try expectEqual(u1, TInt(.unsigned, 1));
    try expectEqual(u8, TInt(.unsigned, 8));
    try expectEqual(i8, TInt(.signed, 8));
    try expectEqual(i16, TInt(.signed, 16));
}

/// Constructs a specific *float* type.
pub fn TFloat(comptime bit_count: u8) type {
    return @Type(.{ .float = .{ .bits = bit_count } });
}

test TFloat {
    try expectEqual(f16, TFloat(16));
    try expectEqual(f32, TFloat(32));
    try expectEqual(f64, TFloat(64));
    try expectEqual(f128, TFloat(128));
}

/// Returns the child of `P`.
/// Issue key specs:
/// - Panics when `P` has no child.
pub fn Child(comptime P: type) type {
    return switch (@typeInfo(P)) {
        .array => |info| info.child,
        .optional => |info| info.child,
        .pointer => |info| info.child,
        .vector => |info| info.child,
        else => @compileError(comptimePrint(
            "Expected array, optional, pointer or vector type, found '{s}'",
            .{@typeName(P)},
        )),
    };
}

/// Returns promoted `T` with bits being next power of two.
pub fn NextPowerOf2(T: type) type {
    comptime assertType(T, .{ .int, .float });
    return switch (@typeInfo(T)) {
        .int => |info| TInt(info.signedness, nextPowerOf2(info.bits) catch {
            @compileError("Overflows 'usize'");
        }),
        .float => |info| TFloat(nextPowerOf2(info.bits) catch {
            @compileError("Overflows 'usize'");
        }),
        else => unreachable,
    };
}

test NextPowerOf2 {
    try expectEqual(u1, NextPowerOf2(u0));
    try expectEqual(u16, NextPowerOf2(u8));
    try expectEqual(f32, NextPowerOf2(f16));
}

/// Verify properties of namespace `ctx` against `decls`.
/// Useful for handling custom functions provided by the user,
/// e.g. in library code to allow flexibility.
/// Example `decls`:
/// .{
///     .{ "fn"  , T_ret, .{ T_arg1, T_arg2 } }, // function
///     .{ "decl", T    , .{} },                 // declaration
///     ...
/// }
/// Issue key specs:
/// - Panics when context fail verification.
pub fn verifyContext(comptime ctx: type, comptime decls: anytype) void {
    assertComptime(@src().fn_name);
    assertType(ctx, .{.@"struct"});
    assertType(@TypeOf(decls), .{.@"struct"});

    inline for (decls, 0..) |decl, i| {

        // check 'decl' -->

        if (@typeInfo(@TypeOf(decl)) != .@"struct") {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `decls`), expected tuple found '{s}'",
                .{ i, @typeName(@TypeOf(decl)) },
            ));
        }
        if (decl.len != 3) {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `decls`), expected 3 fields found {d}",
                .{ i, decl.len },
            ));
        }

        const decl_0_type = @TypeOf(decl[0]);
        const decl_1_type = @TypeOf(decl[1]);
        const decl_2_type = @TypeOf(decl[2]);

        if (!comptime isString(decl_0_type)) {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `decls`), expected string found '{s}'",
                .{ i, @typeName(decl_0_type) },
            ));
        }
        if (decl_1_type != type) {
            @compileError(std.fmt.comptimePrint(
                "Invalid type specification (index {d} `decls`), expected type found '{s}'",
                .{ i, @typeName(decl_1_type) },
            ));
        }
        if (@typeInfo(decl_2_type) != .@"struct") {
            @compileError(std.fmt.comptimePrint(
                "Invalid function arguments (index {d} `decls`), expected tuple found '{s}'",
                .{ i, @typeName(decl_2_type) },
            ));
        }

        // check 'ctx' against 'decl' -->

        const name = decl[0];
        const T_final = decl[1];
        const fn_args = decl[2];

        if (!@hasDecl(ctx, name)) {
            @compileError(std.fmt.comptimePrint(
                "No declaration '{s}' found in context",
                .{name},
            ));
        }

        const T_actual = @TypeOf(@field(ctx, name));

        switch (@typeInfo(T_actual)) {
            .@"fn" => assertFn(T_actual, fn_args, T_final),
            else => {
                if (fn_args.len > 0) {
                    @compileError(std.fmt.comptimePrint(
                        "Function parameter types was specified for non-function '{s}' (in `decls`)",
                        .{name},
                    ));
                }
                if (T_actual != T_final) {
                    @compileError(std.fmt.comptimePrint(
                        "Type mismatch for '{s}': expected '{s}' (in `decls`), found '{s}' (in `ctx`).",
                        .{ name, @typeName(T_final), @typeName(T_actual) },
                    ));
                }
            },
        }
    }
}

test verifyContext {
    comptime {
        const ctx = struct {
            const someConst: u8 = 4;
            fn hash(data: u64) u64 {
                return std.hash.Wyhash.hash(data);
            }
        };

        const decls = .{
            .{ "someConst", u8, .{} },
            .{ "hash", u64, .{u64} },
        };

        verifyContext(ctx, decls);

        // TODO! test compile error case (currently not possible)
    }
}

/// Check if `T` is of string type (only considers ASCII strings).
/// Return true for:
/// - slice of bytes.
/// - array of bytes.
/// - many item pointer to byte (0-terminated).
/// - single item pointer to array of bytes.
/// - c pointer to byte (for safe handling use 'std.mem.span' to implicitly check for null terminator).
pub fn isString(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .array => |arr| arr.child == u8,
        .pointer => |ptr| switch (ptr.size) {
            .Slice => ptr.child == u8,
            .Many => b: {
                const sentinel_ptr = ptr.sentinel orelse break :b false;
                const x = ptr.child == u8;
                const y = @as(*align(1) const ptr.child, @ptrCast(sentinel_ptr)).* == @as(u8, 0);
                break :b (x and y);
            },
            .One => switch (@typeInfo(ptr.child)) {
                .array => |arr| arr.child == u8,
                else => false,
            },
            .C => ptr.child == u8,
        },
        else => false,
    };
}

test isString {
    try expectEqual(true, isString([4]u8)); // array
    try expectEqual(true, isString([]const u8)); // slice
    try expectEqual(true, isString([]u8)); // slice mutable
    try expectEqual(true, isString([*:0]const u8)); // many-item pointer
    try expectEqual(true, isString(*const [4:0]u8)); // single-item pointer
    try expectEqual(true, isString([*c]const u8)); // c pointer
    try expectEqual(true, isString(@TypeOf("literal"))); // literal
    //
    try expectEqual(false, isString(u8)); // not string
    try expectEqual(false, isString([*]const u8)); // not terminated
}

/// Assert that type `T` is pointer to an array.
/// If successful returns the child type on the array.
/// Issue key specs:
/// - Panics when `T` fail assertion.
pub fn PointerArrayChildType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .pointer) {
        @compileError("Expected pointer, found " ++ @typeName(T));
    }
    switch (info.pointer.size) {
        .Slice, .Many => {
            return info.pointer.child;
        },
        else => {
            const info_child = @typeInfo(info.pointer.child);
            if (info_child != .array) {
                @compileError("Expected array child, found " ++ @typeName(info.pointer.child));
            }
            return info_child.array.child;
        },
    }
}

test PointerArrayChildType {
    comptime {
        const T = u8;
        var C: type = undefined;
        const array = [_]T{ 4, 4, 4, 4 };

        // test slice
        const slice: []const T = &array;
        C = PointerArrayChildType(@TypeOf(slice));
        expectEqual(T, C) catch unreachable;

        // test many-item pointer
        const many: [*]const T = &array;
        C = PointerArrayChildType(@TypeOf(many));
        expectEqual(T, C) catch unreachable;

        // test one pointer
        const ptr: *const [array.len]T = &array;
        C = PointerArrayChildType(@TypeOf(ptr));
        expectEqual(T, C) catch unreachable;

        // TODO! test compile error case (currently not possible)
    }
}
