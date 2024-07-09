const std = @import("std");

const expectEqual = std.testing.expectEqual;

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
                @compileError("Expected array, found " ++ @typeName(info.Pointer.child));
            }
            return info_child.Array.child;
        },
    }
}

test PointerArrayChildType {
    const T = u8;
    const array = [_]T{ 4, 4, 4, 4 };

    comptime { // test array pointer
        const ptr: *const [array.len]T = &array;
        const C = PointerArrayChildType(@TypeOf(ptr));
        expectEqual(T, C) catch unreachable;
    }

    comptime { // test many-item pointer
        const many: [*]const T = &array;
        const C = PointerArrayChildType(@TypeOf(many));
        expectEqual(T, C) catch unreachable;
    }

    comptime { // test slice
        const slice: []const T = &array;
        const C = PointerArrayChildType(@TypeOf(slice));
        expectEqual(T, C) catch unreachable;
    }
}

/// Assert that type `Fn` is of the form: 'fn (in...) out'.
/// `in` should be a tuple of expected parameter types (ordered).
/// `out' should be the expected return type.
pub fn assertFn(comptime Fn: type, comptime in: anytype, comptime out: type) void {
    // check function type
    const fn_type_info = @typeInfo(Fn);
    if (fn_type_info != .Fn) {
        @compileError("Expected function for 'Fn' argument, found " ++ @typeName(Fn));
    }

    // check input type
    const in_type = @TypeOf(in);
    const in_type_info = @typeInfo(in_type);
    if (in_type_info != .Struct) {
        @compileError("Expected tuple for 'in' argument, found " ++ @typeName(in_type));
    }

    // check number of parameters
    const params = fn_type_info.Fn.params;
    if (params.len != in_type_info.Struct.fields.len) {
        @compileError("Expected same parameter count, found " ++
            std.fmt.comptimePrint("{d}", .{params.len}) ++ "!=" ++
            std.fmt.comptimePrint("{d}", .{in_type_info.Struct.fields.len}));
    }

    // check parameter types
    inline for (params, 0..) |param, i| {
        const expect_type = param.type.?;
        const actual_type = in[i];
        if (expect_type != actual_type) {
            @compileError("Type mismatch for parameter " ++ std.fmt.comptimePrint("{d}", .{i}) ++
                ", expected " ++ @typeName(expect_type) ++
                ", found " ++ @typeName(actual_type));
        }
    }

    // check return type
    const return_type = fn_type_info.Fn.return_type.?;
    if (return_type != out) {
        @compileError("Return type mismatch, expected " ++
            @typeName(out) ++ ", found " ++ @typeName(return_type));
    }
}

test assertFn {
    comptime { // test successful case
        const foo_fn_type = fn (a: u32, b: u32) u32;
        assertFn(foo_fn_type, .{ u32, u32 }, u32);
    }
}
