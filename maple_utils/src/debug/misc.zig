const std = @import("std");

const panic = std.debug.panic;

/// Assert that `dictum` is true, panic otherwise.
/// Display a formatted message with `fmt` and `args`.
pub fn assertAndMsg(dictum: bool, comptime fmt: []const u8, args: anytype) void {
    if (dictum) return else panic(fmt, args);
}
