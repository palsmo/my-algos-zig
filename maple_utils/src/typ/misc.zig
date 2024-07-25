const std = @import("std");

const debug = @import("../debug/root.zig");

const assertAndMsg = debug.assertAndMsg;
const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

/// Assert that type `T_fn` is of the form: 'fn (`args`...) `T_ret`'.
/// `args` should be a tuple of expected parameter types (ordered).
/// `T_ret` should be the expected return type.
pub fn assertFn(comptime T_fn: type, comptime args: anytype, comptime T_ret: type) void {
    // check `T_fn` type
    const Fn_info = @typeInfo(T_fn);
    if (Fn_info != .Fn) {
        @compileError("Expected function-type for `F` argument, found '" ++ @typeName(T_fn) ++ "'.");
    }

    // check `args` type
    const I = @TypeOf(args);
    const I_info = @typeInfo(I);
    if (I_info != .Struct or !I_info.Struct.is_tuple) {
        @compileError("Expected tuple for `in` argument, found '" ++ @typeName(I) ++ "'.");
    }

    // check number of parameters
    const params = Fn_info.Fn.params;
    if (params.len != I_info.Struct.fields.len) {
        @compileError("Expected same parameter count, found " ++
            std.fmt.comptimePrint("{d}", .{params.len}) ++ "!=" ++
            std.fmt.comptimePrint("{d}", .{I_info.Struct.fields.len}));
    }

    // check parameter types
    inline for (params, 0..) |param, i| {
        const Expect = param.type.?;
        const actual = args[i];
        if (Expect != actual) {
            @compileError("Type mismatch for parameter " ++ std.fmt.comptimePrint("{d}", .{i}) ++
                ", expected '" ++ @typeName(Expect) ++
                "', found '" ++ @typeName(actual) ++ "'.");
        }
    }

    // check return type
    const Ret = Fn_info.Fn.return_type.?;
    if (Ret != T_ret) {
        @compileError("Return type mismatch, expected '" ++
            @typeName(T_ret) ++ "', found '" ++ @typeName(Ret) ++ "'.");
    }
}

test assertFn {
    comptime { // test correct case
        const foo_fn_type = fn (a: u32, b: u32) u32;
        assertFn(foo_fn_type, .{ u32, u32 }, u32);
    }
    { // TODO! test compile error case (currently not possible)
    }
}

/// Assert that type `T` matches any of `types`.
/// `types` should be a tuple of 'std.builtin.Type(enum)', example: .{ .Int, .Float }
/// Optionally display a formatted message with `fmt` and `args`.
pub fn assertType(comptime T: type, comptime types: anytype, comptime fmt: []const u8, comptime args: anytype) void {
    assertAndMsg(@inComptime(), "Function 'assertType' is invalid runtime (prefix with 'comptime').", .{});

    const T_types = @TypeOf(types);
    switch (@typeInfo(T_types)) {
        .Struct => |info| if (!info.is_tuple) {
            @compileError(std.fmt.comptimePrint("Expected tuple (`types`), found '{s}'", .{@typeName(T_types)}));
        },
        else => .{},
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

    // fail message
    if (fmt.len > 0) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else {
        @compileError(std.fmt.comptimePrint(
            "Type '{s}' (`T`) does not match any of .{{s}} (`types`).",
            .{ @typeName(T), types_str },
        ));
    }
}

test assertType {
    // test correct case
    comptime {
        const types = .{ .Int, .Bool };
        assertType(u8, types, "", .{});
        assertType(bool, types, "", .{});
    }
    { // TODO! test compile error case (currently not possible)
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
    comptime assertType(ctx, .{.Struct}, "Expected namespace (`ctx`), found '{s}'.", .{@typeName(ctx)});
    comptime assertType(@TypeOf(decls), .{.Struct}, "Expected tuple (`decls`), found '{s}'.", .{@typeName(@TypeOf(decls))});

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
            .Fn => {
                if (fn_args.len == 0) {
                    @compileError(std.fmt.comptimePrint(
                        "Missing function parameter types for '{s}' (in `decls`).",
                        .{name},
                    ));
                }
            },
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
    const T = u8;
    const array = [_]T{ 4, 4, 4, 4 };

    comptime { // test slice
        const slice: []const T = &array;
        const C = PointerArrayChildType(@TypeOf(slice));
        expectEqual(T, C) catch unreachable;
    }

    comptime { // test many-item pointer
        const many: [*]const T = &array;
        const C = PointerArrayChildType(@TypeOf(many));
        expectEqual(T, C) catch unreachable;
    }

    comptime { // test one pointer
        const ptr: *const [array.len]T = &array;
        const C = PointerArrayChildType(@TypeOf(ptr));
        expectEqual(T, C) catch unreachable;
    }
    { // TODO! test compile error case (currently not possible)
    }
}
