const std = @import("std");

const expectEqual = std.testing.expectEqual;
const panic = std.debug.panic;

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

/// Assert that type `T` matches any of `types`.
/// Argument `types` should be a tuple of `std.builtin.Type(enum)`.
/// E.g. assertType(T, .{ .Int, .Float });
pub fn assertType(comptime T: type, comptime types: anytype) void {
    const S = @TypeOf(types);
    const S_info = @typeInfo(S);
    if (S_info != .Struct or !S_info.Struct.is_tuple) {
        @compileError("Expected tuple for `types` argument, found '" ++ @typeName(S) ++ "'.");
    }

    const T_info = @typeInfo(T);
    inline for (types) |t| {
        if (@TypeOf(t) != @TypeOf(.enum_literal)) {
            @compileError("Non 'std.builtin.Type' passed as argument in `types`.");
        }
        if (T_info == t) return;
    }
    @compileError("Type '" ++ @typeName(T) ++ "' does not match any in `types`.");
}

test assertType {
    comptime { // test correct case
        const T = u8;
        const B = bool;
        const types = .{ .Int, .Bool };
        assertType(T, types);
        assertType(B, types);
    }
    { // TODO! test compile error case (currently not possible)
    }
}

/// Assert that type `Fn` is of the form: 'fn (in...) out'.
/// `in` should be a tuple of expected parameter types (ordered).
/// `Out` should be the expected return type.
pub fn assertFn(comptime Fn: type, comptime in: anytype, comptime Out: type) void {
    // check `Fn` type
    const Fn_info = @typeInfo(Fn);
    if (Fn_info != .Fn) {
        @compileError("Expected function-type for `F` argument, found '" ++ @typeName(Fn) ++ "'.");
    }

    // check `in` type
    const I = @TypeOf(in);
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
        const actual = in[i];
        if (Expect != actual) {
            @compileError("Type mismatch for parameter " ++ std.fmt.comptimePrint("{d}", .{i}) ++
                ", expected '" ++ @typeName(Expect) ++
                "', found '" ++ @typeName(actual) ++ "'.");
        }
    }

    // check return type
    const Return = Fn_info.Fn.return_type.?;
    if (Return != Out) {
        @compileError("Return type mismatch, expected '" ++
            @typeName(Out) ++ "', found '" ++ @typeName(Return) ++ "'.");
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
