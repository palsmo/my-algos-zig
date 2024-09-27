// Author: palsmo
// Status: In Progress

const std = @import("std");

const prj = @import("project");
const mod_assert = @import("../assert/root.zig");
const mod_math = @import("../math/root.zig");
const mod_type = @import("../type/root.zig");

const NextPowerOf2 = mod_type.misc.NextPowerOf2;
const TInt = mod_type.misc.TInt;
const ValueError = prj.ValueError;
const assertType = mod_assert.assertType;
const int = mod_math.int;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

const Error = error{
    NonDigitChar,
};

pub fn charsToNumber(buf: []const u8, T: type) (Error || ValueError)!T {
    comptime assertType(T, .{ .int, .comptime_int });
    if (buf.len == 0) return;

    const max_safe_value = int.max(T) / 10;
    var ret: T = 0;

    for (buf) |c| {
        // * no room to fit next digit
        if (ret > max_safe_value) return error.Overflow;
        if (c < '0' or c > '9') return error.NonDigitChar;
        const digit = c - '0';
        // * digit won't fit within last
        if (ret == max_safe_value and digit > int.max(T) % 10) return error.Overflow;
        ret = ret * 10 + digit;
    }

    return ret;
}

test charsToNumber {
    try expectEqual(@as(u8, 42), charsToNumber("42", u8));
    try expectEqual(@as(u8, 255), charsToNumber("255", u8));
    try expectError(error.Overflow, charsToNumber("256", u8));
    try expectEqual(error.NonDigitChar, charsToNumber("12E", u8));
}
