//! Author: Palsmo
//! Status: In Progress

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertComptime = mod_assert.misc.assertComptime;
const assertFn = mod_assert.misc.assertFn;
const assertType = mod_assert.misc.assertType;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Verify properties of namespace `ctx` against `decls`.
/// Useful for handling custom functions provided by the user,
/// e.g. in library code to allow flexibility.
/// Example `decls`:
/// .{
///     .{ "fn"  , T_ret, .{ T_arg1, T_arg2 } }, // function
///     .{ "decl", T    , .{} },                 // simple declaration
///     .{ ... },
/// }
pub fn verifyContext(comptime ctx: type, comptime decls: anytype) void {
    assertComptime(@src().fn_name);
    assertType(ctx, .{.Struct}, "fn {s}.ctx", .{@src().fn_name});
    assertType(@TypeOf(decls), .{.Struct}, "fn {s}.decls", .{@src().fn_name});

    inline for (decls, 0..) |decl, i| {

        // check 'decl' -->

        if (@typeInfo(@TypeOf(decl)) != .Struct) {
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
        if (@typeInfo(decl_2_type) != .Struct) {
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
            .Fn => assertFn(T_actual, fn_args, T_final),
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
        .Array => |arr| arr.child == u8,
        .Pointer => |ptr| switch (ptr.size) {
            .Slice => ptr.child == u8,
            .Many => b: {
                const sentinel_ptr = ptr.sentinel orelse break :b false;
                const x = ptr.child == u8;
                const y = @as(*align(1) const ptr.child, @ptrCast(sentinel_ptr)).* == @as(u8, 0);
                break :b (x and y);
            },
            .One => switch (@typeInfo(ptr.child)) {
                .Array => |arr| arr.child == u8,
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
    // test negatives
    try expectEqual(false, isString(u8)); // not string
    try expectEqual(false, isString([*]const u8)); // not terminated
}

/// Assert that type `T` is pointer to an array.
/// If successful returns the child type on the array.
pub fn PointerArrayChildType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .Pointer) {
        @compileError("Expected pointer, found " ++ @typeName(T));
    }
    switch (info.Pointer.size) {
        .Slice, .Many => {
            return info.Pointer.child;
        },
        else => {
            const info_child = @typeInfo(info.Pointer.child);
            if (info_child != .Array) {
                @compileError("Expected array child, found " ++ @typeName(info.Pointer.child));
            }
            return info_child.Array.child;
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
