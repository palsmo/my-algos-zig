const std = @import("std");

const Declaration = std.builtin.Type.Declaration;
const EnumField = std.builtin.Type.EnumField;
const math = std.math;

/// Combine two enums into one, `a` takes precedence over `b`.
/// Will respect overridden values, falling back to ordinal 0..
/// The returned enum will conform to `T`, in case of 'null'
/// the result will instead use the smallest type that fits all.
fn EnumCombine(comptime a: type, comptime b: type, comptime T: ?type) type {
    const a_info = @typeInfo(a);
    const b_info = @typeInfo(b);

    if (a_info != .Enum or b_info != .Enum) {
        @compileError("Arguments `a` and `b` has to be enums.");
    }

    const a_ = a_info.Enum;
    const b_ = b_info.Enum;
    const hasher = std.hash.Murmur3_32;

    const tag_type, const fields = blk: {
        const len = a_.fields.len + b_.fields.len;
        if (len == 0) break :blk .{ T orelse u0, [_]EnumField{} };

        var name_set = [_][]const u8{""} ** len; // set of names indexed by their hash
        var value_set = [_]comptime_int{0} ** len; // set of values indexed by their hash

        var max_value: comptime_int = undefined; // biggest value found among fields
        var result: [len]EnumField = undefined; // collection of unique fields
        var ordinal: comptime_int = 0; // current ordinal value
        var uniques: comptime_int = 0; // number of unique fields

        const fields_ab = [_][]const EnumField{ a_.fields, b_.fields };
        for (fields_ab) |fields| {
            for (fields) |field| {

                // determine unique name
                const name = field.name; // if already exists, ignore
                const name_hash = hasher.hash(name);
                const i = name_hash % len;
                const name_ = name_set[i];
                if (name_hash == hasher.hash(name_)) {
                    if (std.mem.eql(u8, name, name_)) continue;
                } else name_set[i] = name;

                // determine unique value
                var value = field.value; // if already exists, find available
                while (ordinal <= uniques) : (ordinal += 1) {
                    const value_hash = hasher.hashUint32(@as(u32, value));
                    const j = value_hash % len;
                    const value_ = value_set[j];
                    if (value != value_) {
                        value_set[j] = value;
                        break;
                    }
                    value = ordinal;
                }

                // (tag_type)
                if (T != null or uniques == 0) {
                    max_value = value;
                } else if (max_value < value) {
                    max_value = value;
                }

                result[uniques] = .{ .name = name, .value = value };
                uniques += 1;
            }
        }

        const tag_type = T orelse math.IntFittingRange(0, max_value);
        const fields = result[0..uniques].*;
        break :blk .{ tag_type, fields };
    };

    const is_exhaustive = a_.is_exhaustive and b_.is_exhaustive;

    const data = .{
        .tag_type = tag_type,
        .fields = &fields,
        .decls = .{},
        .is_exhaustive = is_exhaustive,
    };

    return @Type(.{ .Enum = data });
}

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "enum {} + enum {} = enum {}" {
    const a = enum {};
    const b = enum {};
    const r = EnumCombine(a, b, null);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.tag_type, u0);
    try expectEqual(r_info.fields.len, 0);
    try expectEqual(r_info.is_exhaustive, true);
}

test "enum { a } + enum { b } = enum { a, b }" {
    const a = enum { a };
    const b = enum { b };
    const r = EnumCombine(a, b, null);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.tag_type, u1);
    try expectEqual(r_info.fields.len, 2);
    try expectEqual(r_info.is_exhaustive, true);
    try expectEqual(r_info.fields[0].value, 0);
    try expectEqual(r_info.fields[1].value, 1);
    try expectEqualStrings(r_info.fields[0].name, "a");
    try expectEqualStrings(r_info.fields[1].name, "b");
}

test "enum { a, b } + enum { b } = enum { a, b }" {
    const a = enum { a };
    const b = enum { b };
    const r = EnumCombine(a, b, null);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.tag_type, u1);
    try expectEqual(r_info.fields.len, 2);
    try expectEqual(r_info.is_exhaustive, true);
    try expectEqual(r_info.fields[0].value, 0);
    try expectEqual(r_info.fields[1].value, 1);
    try expectEqualStrings(r_info.fields[0].name, "a");
    try expectEqualStrings(r_info.fields[1].name, "b");
}

test "enum { a, b } + enum { c } = enum { a, b, c }" {
    const ab = enum { a, b };
    const c = enum { c };
    const r = EnumCombine(ab, c, null);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.tag_type, u2);
    try expectEqual(r_info.fields.len, 3);
    try expectEqual(r_info.is_exhaustive, true);
    try expectEqual(r_info.fields[0].value, 0);
    try expectEqual(r_info.fields[1].value, 1);
    try expectEqual(r_info.fields[2].value, 2);
    try expectEqualStrings(r_info.fields[0].name, "a");
    try expectEqualStrings(r_info.fields[1].name, "b");
    try expectEqualStrings(r_info.fields[2].name, "c");
}

test "respect overridden value" {
    const a = enum(u8) { a = 77 };
    const bc = enum { b, c };
    const r = EnumCombine(a, bc, null);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.fields[0].value, 77);
    try expectEqual(r_info.fields[1].value, 0);
    try expectEqual(r_info.fields[2].value, 1);
}

test "conform to given enum type" {
    // empty
    const a = enum {};
    const b = enum {};
    const r = EnumCombine(a, b, u12);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.tag_type, u12);
    // non-empty
    const c = enum { c };
    const s = EnumCombine(a, c, u16);
    const s_info = @typeInfo(s).Enum;
    try expectEqual(s_info.tag_type, u16);
}

test "handle non-exhaustive case" {
    const a = enum(u5) { a, _ };
    const b = enum { b };
    const r = EnumCombine(a, b, u5);
    const r_info = @typeInfo(r).Enum;
    try expectEqual(r_info.is_exhaustive, false);
}
