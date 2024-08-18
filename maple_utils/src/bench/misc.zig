//! Author: palsmo
//! Status: Done
//! About: Benchmark Functionality

const std = @import("std");

const mod_assert = @import("../assert/root.zig");

const assertType = mod_assert.misc.assertType;
const panic = std.debug.panic;

pub fn Benchmark(comptime func: anytype) type {
    comptime assertType(@TypeOf(func), .{.Fn});

    return struct {
        const Self = @This();
        const T_func = @TypeOf(func);

        // struct fields
        func: T_func = func,
        func_args: ?std.meta.ArgsTuple(T_func) = null,
        time_avg: u64 = 0, // output from latest 'self.run'

        /// Specify `func_args` for calling 'self.func' with.
        pub fn args(self: *Self, func_args: anytype) void {
            comptime assertType(func_args, .{.Struct});
            self.func_args = func_args;
        }

        /// Warmup cache by running 'self.func' `n` times.
        pub fn warmup(self: *const Self, n: u64) void {
            switch (n) {
                0 => return,
                1 => _ = @call(.auto, self.func, self.func_args),
                else => for (1..n) |_| {
                    _ = @call(.auto, self.func, self.func_args);
                },
            }
        }

        /// Benchmark 'self.func' for `n` iterations.
        /// Issue key specs:
        /// - Throws error when 'std.time.Timer' is unsupported by the system.
        pub fn run(self: *Self, n: u64) !u64 {
            const func_args = self.func_args orelse {
                panic("Function arguments are not set, (call 'args()' before 'run()').", .{});
            };
            switch (n) {
                0 => return 0,
                1 => {
                    const timer = try std.time.Timer.start();
                    _ = @call(.auto, self.func, func_args);
                    return timer.read();
                },
                else => {
                    const timer = try std.time.Timer.start();
                    for (1..n) |_| {
                        _ = @call(.auto, self.func, func_args);
                    }
                    const time = timer.read();
                    return time / n;
                },
            }
        }

        /// Print message for latest benchmark.
        pub fn print(self: *const Self) void {
            const fmt = "Function '{s}' executed at (average) {}\n";
            std.debug.print(fmt, .{ @typeName(T_func), std.fmt.fmtDuration(self.time_avg) });
        }
    };
}

test Benchmark {
    const bench = Benchmark(std.math.pow){};

    bench.args(.{ u8, 2, 3 });
    bench.warmup(4);
    bench.run(100);
    bench.print();
}
