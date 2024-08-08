const std = @import("std");

const mod_math = @import("../math/root.zig");

const comptimePrint = std.fmt.comptimePrint;
const panic = std.debug.panic;
const isPowerOf2 = mod_math.misc.isPowerOf2;

/// Assert that `dictum` is true, panic otherwise.
/// Display a formatted message with `fmt` and `args`.
pub inline fn assertAndMsg(dictum: bool, comptime fmt: []const u8, args: anytype) void {
    if (dictum) return;
    switch (@inComptime()) {
        true => @compileError(comptimePrint(fmt, args)),
        false => panic(fmt, args),
    }
}

/// Assert this function is executed comptime.
/// Prints a message with `calling_fn_name`.
pub inline fn assertComptime(comptime calling_fn_name: []const u8) void {
    switch (@inComptime()) {
        true => {},
        false => panic(
            "Function '{s}' is invalid runtime (prefix with 'comptime').",
            .{calling_fn_name},
        ),
    }
}
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
            @compileError(comptimePrint(
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
            @compileError(comptimePrint(
                "Expected tuple type for `args` argument, found '{s}'",
                .{@typeName(T_args)},
            ));
        },
    }

    // check number of parameters
    const params = T_fn_info.Fn.params;
    if (params.len != T_args_info.Struct.fields.len) {
        @compileError("Expected same parameter count, found " ++
            comptimePrint("{d}", .{params.len}) ++ "!=" ++
            comptimePrint("{d}", .{T_args_info.Struct.fields.len}));
    }

    // check parameter types
    inline for (params, 0..) |param, i| {
        const T_arg_actual = param.type.?;
        const T_arg: type = if (@TypeOf(args[i]) == type) args[i] else {
            @compileError(comptimePrint(
                "Invalid declaration (index {d} `args`), expected type found '{s}'",
                .{ i, @typeName(@TypeOf(args[i])) },
            ));
        };
        if (T_arg_actual != T_arg) {
            @compileError(comptimePrint(
                "Type mismatch for parameter {d}, expected '{s}' found '{s}'",
                .{ i, @typeName(T_arg), @typeName(T_arg_actual) },
            ));
        }
    }

    // check return type
    const Ret = T_fn_info.Fn.return_type.?;
    if (Ret != T_ret) {
        @compileError(comptimePrint(
            "Type mismatch for return, expected '{s}' (`T_ret`) found '{s}' (in `T_fn`).",
            .{ @typeName(T_ret), @typeName(T_fn) },
        ));
    }
}

test assertFn {
    comptime {
        const foo_fn_type = fn (a: u32, b: u32) u32;
        assertFn(foo_fn_type, .{ u32, u32 }, u32);
        // TODO! test panic case (currently not possible)
    }
}

/// Assert that `int` is some power of two.
pub inline fn assertPowerOf2(int: anytype) void {
    comptime assertType(@TypeOf(int), .{ .Int, .ComptimeInt }, "fn {s}.int", .{@src().fn_name});
    if (isPowerOf2(int)) return;
    panic("Value is not a power of two, found '{}'", .{int});
}

test assertPowerOf2 {
    assertPowerOf2(1);
    assertPowerOf2(2);
    // TODO! test panic case (currently not possible)
    //assertPowOf2(0);
    //assertPowOf2(3);
}

/// Assert that type `T` matches any of `types`.
/// `types` should be a tuple of 'std.builtin.Type(enum)', example: .{ .Int, .Float }
/// Display some 'identifier' with `fmt` + `args` on assertion fail.
pub fn assertType(comptime T: type, comptime types: anytype, comptime fmt: []const u8, args: anytype) void {
    assertComptime(@src().fn_name);

    const T_types = @TypeOf(types);
    switch (@typeInfo(T_types)) {
        .Struct => {},
        else => @compileError(comptimePrint(
            "Expected tuple (`types`), found '{s}'",
            .{@typeName(T_types)},
        )),
    }

    comptime var types_str: []const u8 = "";

    inline for (types, 0..) |t, i| {
        // check 't' is enum literal
        if (@TypeOf(t) != @TypeOf(.enum_literal)) {
            @compileError(comptimePrint(
                "Invalid declaration (index {d} `types`), expected enum literal found '{s}'",
                .{ i, @typeName(@TypeOf(t)) },
            ));
        }
        // check 't' is field of 'std.builtin.Type'
        if (!@hasField(std.builtin.Type, @tagName(t))) {
            @compileError(comptimePrint(
                "Invalid declaration (index {d} `types`), '{s}' is not a member of 'std.builtin.Type'",
                .{ i, @tagName(t) },
            ));
        }
        // check `T` is kind `t`
        if (i > 0) types_str = types_str ++ ", ";
        types_str = types_str ++ "." ++ @tagName(t);
        if (@typeInfo(T) == t) return;
    }

    @compileError(comptimePrint(
        "Type '{s}' (`{s}`) does not match any of .{{ {s} }}",
        .{ @typeName(T), comptimePrint(fmt, args), types_str },
    ));
}

test assertType {
    comptime {
        const types = .{ .Int, .Bool };
        assertType(u8, types, "test assertType.types", .{});
        assertType(bool, types, "test assertType.types", .{});
        // TODO! test panic case (currently not possible)
    }
}
