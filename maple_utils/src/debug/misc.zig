const std = @import("std");

const panic = std.debug.panic;

/// Assert that `dictum` is true, panic otherwise.
/// Display a formatted message with `fmt` and `args`.
pub inline fn assertAndMsg(dictum: bool, comptime fmt: []const u8, args: anytype) void {
    if (dictum) return;
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else {
        panic(fmt, args);
    }
}

/// Assert this function is executed comptime, prints a message mentioning `calling_fn_name`.
pub inline fn assertComptime(comptime calling_fn_name: []const u8) void {
    assertAndMsg(
        @inComptime(),
        "Function '{s}' is invalid runtime (prefix with 'comptime').",
        .{calling_fn_name},
    );
}
