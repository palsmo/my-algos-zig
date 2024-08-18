pub const assert = @import("./src/assert/root.zig");
pub const bench = @import("./src/bench/root.zig");
pub const math = @import("./src/math/root.zig");

test {
    _ = bench;
}
