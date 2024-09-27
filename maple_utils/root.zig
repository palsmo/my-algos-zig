// Author: palsmo

pub const assert = @import("./src/assert/root.zig");
pub const math = @import("./src/math/root.zig");
pub const mem = @import("./src/mem/root.zig");

test {
    _ = assert;
    _ = math;
    _ = mem;
}
