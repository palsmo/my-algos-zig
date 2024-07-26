//! Author: Palsmo
//! Status: In Progress

const std = @import("std");

const maple_debug = @import("../debug/root.zig");

const assertComptime = maple_debug.assertComptime;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Assert that type `T_fn` is of the form: 'fn (`args`...) `T_ret`'.
/// `args` should be a tuple of expected parameter types (ordered).
/// `T_ret` is the expected function return type.
pub fn assertFn(comptime T_fn: type, comptime args: anytype, comptime T_ret: type) void {
    assertComptime(@src().fn_name);

    // check `T_fn` type
    const T_fn_info = @typeInfo(T_fn);
    switch (T_fn_info) {
        .Fn => {},
        else => {
            @compileError(std.fmt.comptimePrint(
                "Expected function type for `T_fn` argument, found '{s}'",
                .{@typeName(T_fn)},
            ));
        },
    }

    // check `args` type
    const T_args = @TypeOf(args);
    const T_args_info = @typeInfo(T_args);
    switch (T_args_info) {
        .Struct => {},
        else => {
            @compileError(std.fmt.comptimePrint(
                "Expected tuple type for `args` argument, found '{s}'",
                .{@typeName(T_args)},
            ));
        },
    }

    // check number of parameters
    const params = T_fn_info.Fn.params;
    if (params.len != T_args_info.Struct.fields.len) {
        @compileError("Expected same parameter count, found " ++
            std.fmt.comptimePrint("{d}", .{params.len}) ++ "!=" ++
            std.fmt.comptimePrint("{d}", .{T_args_info.Struct.fields.len}));
    }

    // check parameter types
    inline for (params, 0..) |param, i| {
        const T_arg_actual = param.type.?;
        const T_arg: type = if (@TypeOf(args[i]) == type) args[i] else {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `args`), expected type found '{s}'",
                .{ i, @typeName(@TypeOf(args[i])) },
            ));
        };
        if (T_arg_actual != T_arg) {
            @compileError(std.fmt.comptimePrint(
                "Type mismatch for parameter {d}, expected '{s}' found '{s}'",
                .{ i, @typeName(T_arg), @typeName(T_arg_actual) },
            ));
        }
    }

    // check return type
    const Ret = T_fn_info.Fn.return_type.?;
    if (Ret != T_ret) {
        @compileError(std.fmt.comptimePrint(
            "Type mismatch for return, expected '{s}' (`T_ret`) found '{s}' (in `T_fn`).",
            .{ @typeName(T_ret), @typeName(T_fn) },
        ));
    }
}

test assertFn {
    comptime {
        const foo_fn_type = fn (a: u32, b: u32) u32;
        assertFn(foo_fn_type, .{ u32, u32 }, u32);

        // TODO! test compile error case (currently not possible)
    }
}

/// Assert that type `T` matches any of `types`.
/// `types` should be a tuple of 'std.builtin.Type(enum)', example: .{ .Int, .Float }
/// `tag` is displayed in the fail message, format could be "<calling_function_name>.<param_name>".
pub fn assertType(comptime T: type, comptime types: anytype, comptime tag: []const u8) void {
    assertComptime(@src().fn_name);

    const T_types = @TypeOf(types);
    switch (@typeInfo(T_types)) {
        .Struct => |info| if (!info.is_tuple) {
            @compileError(std.fmt.comptimePrint("Expected tuple (`types`), found '{s}'", .{@typeName(T_types)}));
        },
        else => {},
    }

    comptime var types_str: []const u8 = "";

    inline for (types, 0..) |t, i| {
        // check 't' is enum literal
        if (@TypeOf(t) != @TypeOf(.enum_literal)) {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `types`), expected enum literal found '{s}'",
                .{ i, @typeName(@TypeOf(t)) },
            ));
        }
        // check 't' is field of 'std.builtin.Type'
        if (!@hasField(std.builtin.Type, @tagName(t))) {
            @compileError(std.fmt.comptimePrint(
                "Invalid declaration (index {d} `types`), '{s}' is not a member of 'std.builtin.Type'",
                .{ i, @tagName(t) },
            ));
        }
        // check `T` is kind `t`
        if (i > 0) types_str = types_str ++ ", ";
        types_str = types_str ++ "." ++ @tagName(t);
        if (@typeInfo(T) == t) return;
    }

    @compileError(std.fmt.comptimePrint(
        "Type '{s}' (`{s}`) does not match any of .{{s}}",
        .{ @typeName(T), tag, types_str },
    ));
}

test assertType {
    comptime {
        const types = .{ .Int, .Bool };
        assertType(u8, types, "types");
        assertType(bool, types, "types");

        // TODO! test compile error case (currently not possible)
    }
}

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
    assertType(ctx, .{.Struct}, "verifyContext.ctx");
    assertType(@TypeOf(decls), .{.Struct}, "verifyContext.decls");

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
