const std = @import("std");

const panic = std.debug.panic;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

/// Compare two values `a` and `b` by an operator `op`.
/// Efficient, comptime evaluates to single comparisons.
pub inline fn cmp(a: anytype, comptime op: std.math.CompareOperator, b: anytype) bool {
    if (@TypeOf(a) != @TypeOf(b)) @compileError("Arguments `a` and `b` are not same type, can't do comparison.");
    return switch (op) {
        .lt => ord(a, b) == .lt,
        .lte => ord(a, b) != .gt,
        .gt => ord(a, b) == .gt,
        .gte => ord(a, b) != .lt,
        .eq => ord(a, b) == .eq,
        .neq => ord(a, b) != .eq,
    };
}

test cmp {
    const a = 1;
    const b = 2;

    // test '<'
    try expect(cmp(a, .lt, b));
    try expect(cmp(b, .lt, a) == false);
    try expect(cmp(a, .lt, a) == false);

    // test '>'
    try expect(cmp(a, .gt, b) == false);
    try expect(cmp(b, .gt, a));
    try expect(cmp(a, .gt, a) == false);

    // test '<='
    try expect(cmp(a, .lte, b));
    try expect(cmp(b, .lte, a) == false);
    try expect(cmp(a, .lte, a));

    // test '>='
    try expect(cmp(a, .gte, b) == false);
    try expect(cmp(b, .gte, a));
    try expect(cmp(a, .gte, a));

    // test '=='
    try expect(cmp(a, .eq, b) == false);
    try expect(cmp(b, .eq, a) == false);
    try expect(cmp(a, .eq, a));

    // test '!='
    try expect(cmp(a, .neq, b));
    try expect(cmp(b, .neq, a));
    try expect(cmp(a, .neq, a) == false);
}

/// Order of `a` relative `b`, asserts same type, returns .lt, .gt or .eq
/// Efficient, comptime evaluates to single type specific code blocks.
/// Not inlined by default since some prongs contain recursion, compiler may decide to inline.
/// Characteristics:
/// Numeric  -> numeric comparison.
/// Array    -> element sequential comparison.
/// Vector   -> element sequential comparison.
/// Pointer  -> [slice, many] element sequential comparison, if same then numeric comparison of sizes.
///             [one, c] pointee comparison.
/// Optional -> if `a` and `b` non-null then value comparison, else null < non-null.
/// Bool     -> false < true.
/// Enum     -> numeric comparison.
/// Union    -> if same active field then value comparison, else field order (first < last).
/// Struct   -> field by field (top to bottom), field-value comparison.
/// Null     -> always equal
/// Void     -> always equal
pub fn ord(a: anytype, b: anytype) std.math.Order {
    const T = @TypeOf(a);
    if (T != @TypeOf(b)) @compileError("Arguments are not same type, can't evaluate order.");

    switch (@typeInfo(T)) {
        .Int, .Float, .ComptimeInt, .ComptimeFloat => {
            if (a < b) return .lt;
            if (a > b) return .gt;
            return .eq;
        },
        .Array => {
            for (a, b) |item_a, item_b| {
                const order = ord(item_a, item_b);
                if (order != .eq) return order;
            }
            return .eq;
        },
        .Vector => |info| {
            for (0..info.len) |i| {
                if (a[i] < b[i]) return .lt;
                if (a[i] > b[i]) return .gt;
            }
            return .eq;
        },
        .Pointer => |info| {
            switch (info.size) {
                .Slice => {
                    // element by element
                    const min_len = @min(a.len, b.len);
                    for (0..min_len) |i| {
                        const order = ord(a[i], b[i]);
                        if (order != .eq) return order;
                    }
                    if (a.len == b.len) return .eq;
                    if (a.len < b.len) return .lt;
                    return .gt;
                },
                .Many => {
                    // element by element
                    const sentinel = std.meta.sentinel(T) orelse {
                        @compileError("Can't compare non-sentinel many-item pointer (lengths can't be established).");
                    };
                    var i: usize = 0;
                    while (true) : (i += 1) {
                        if (ord(a[i], sentinel) == .eq) {
                            return if (ord(b[i], sentinel) == .eq) .eq else .lt;
                        }
                        if (ord(b[i], sentinel) == .eq) return .gt;

                        const order = ord(a[i], b[i]);
                        if (order != .eq) return order;
                    }
                },
                .One, .C => return ord(a.*, b.*),
            }
        },
        .Optional => {
            // null < non-null
            if (a == null and b == null) return .eq;
            if (a == null) return .lt;
            if (b == null) return .gt;
            return ord(a.?, b.?);
        },
        .Bool => {
            if (a == b) return .eq;
            if (a) return .gt;
            return .lt;
        },
        .Enum => {
            if (@intFromEnum(a) < @intFromEnum(b)) return .lt;
            if (@intFromEnum(a) > @intFromEnum(b)) return .gt;
            return .eq;
        },
        .Union => |info| {
            if (info.tag_type != null) {
                // is tagged union, compare the active tags
                const a_tag = std.meta.activeTag(a);
                const b_tag = std.meta.activeTag(b);
                const order = ord(a_tag, b_tag);
                if (order == .eq) {
                    // active fields are same, return order based on field-value
                    const a_val = switch (a) {
                        inline else => |v| v,
                    };
                    const b_val = switch (b) {
                        inline else => |v| v,
                    };
                    return ord(a_val, b_val);
                } else {
                    // active fields are different, return their order (first < last)
                    return order;
                }
            } else {
                @compileError("Can't compare non-tagged union (active field can't be established).");
            }
        },
        .Struct => |info| {
            // compare field by field
            inline for (info.fields) |field| {
                const order = ord(@field(a, field.name), @field(b, field.name));
                if (order != .eq) return order;
            }
            return .eq;
        },
        .Null => return .eq,
        .Void => return .eq,
        else => @compileError("Unsupported type for comparison."),
    }
}

test ord {
    { // test numerics
        const as = .{ @as(u16, 1), @as(i16, -2), @as(f16, 1.0), @as(comptime_int, 1), @as(comptime_float, 1.0) };
        const bs = .{ @as(u16, 2), @as(i16, -1), @as(f16, 2.0), @as(comptime_int, 2), @as(comptime_float, 2.0) };
        inline for (as, bs) |a, b| {
            try expectEqual(.lt, ord(a, b));
            try expectEqual(.gt, ord(b, a));
            try expectEqual(.eq, ord(a, a));
        }
    }

    { // test array
        const T = [2]u8;
        const a = T{ 1, 2 };
        const b = T{ 1, 3 };
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
    }

    { // test vector
        const V = @Vector(2, u8);
        const a = V{ 2, 3 };
        const b = V{ 3, 1 };
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
    }

    { // test pointer
        const T = u8;
        const a = [_]T{ 1, 2 };
        const b = [_]T{ 1, 3 };
        const c = [_]T{ 1, 2, 3 };
        const a_0 = [_:"end"][]const T{ "foo", "bar" };
        const b_0 = [_:"end"][]const T{ "foo", "lem" };
        const c_0 = [_:"end"][]const T{ "foo", "bar", "lem" };

        // slice -->
        const a_slice: []const T = &a;
        const b_slice: []const T = &b;
        const c_slice: []const T = &c;
        try expectEqual(.lt, ord(a_slice, b_slice));
        try expectEqual(.gt, ord(b_slice, a_slice));
        try expectEqual(.eq, ord(a_slice, a_slice));
        try expectEqual(.lt, ord(a_slice, c_slice));

        // many -->
        const a_many: [*:"end"]const []const T = &a_0;
        const b_many: [*:"end"]const []const T = &b_0;
        const c_many: [*:"end"]const []const T = &c_0;
        try expectEqual(.lt, ord(a_many, b_many));
        try expectEqual(.gt, ord(b_many, a_many));
        try expectEqual(.eq, ord(a_many, a_many));
        try expectEqual(.lt, ord(a_many, c_many));

        // one -->
        const a_one: *const []const T = &a_slice;
        const b_one: *const []const T = &b_slice;
        try expectEqual(.lt, ord(a_one, b_one));
        try expectEqual(.gt, ord(b_one, a_one));
        try expectEqual(.eq, ord(a_one, a_one));

        // c -->
        const a_c: [*c]const T = &a[1];
        const b_c: [*c]const T = &b[1];
        try expectEqual(.lt, ord(a_c, b_c));
        try expectEqual(.gt, ord(b_c, a_c));
        try expectEqual(.eq, ord(a_c, a_c));
    }

    { // test optional
        const T = ?u8;
        const a: T = 1;
        const b: T = 2;
        const n: T = null;
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
        // null
        try expectEqual(.lt, ord(n, a));
        try expectEqual(.gt, ord(a, n));
        try expectEqual(.eq, ord(n, n));
    }

    { // test bool
        const a = false;
        const b = true;
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
    }

    { // test enum
        const E = enum { less, greater };
        const a = E.less;
        const b = E.greater;
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
    }

    { // test union
        const U = union(enum) { x: u8, y: u16 };
        const a = U{ .x = 1 };
        const b = U{ .x = 2 };
        const c = U{ .y = 1 };
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
        try expectEqual(.lt, ord(a, c));
    }

    { // test struct
        const S = struct { x: u8, y: u8 };
        const a = S{ .x = 1, .y = 2 };
        const b = S{ .x = 1, .y = 3 };
        try expectEqual(.lt, ord(a, b));
        try expectEqual(.gt, ord(b, a));
        try expectEqual(.eq, ord(a, a));
    }

    { // test null
        const a = null;
        const b = null;
        try expectEqual(.eq, ord(a, b));
    }

    { // test void
        const a = {};
        const b = {};
        try expectEqual(.eq, ord(a, b));
    }
}
