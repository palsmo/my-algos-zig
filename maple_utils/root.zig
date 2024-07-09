pub const math = @import("./src/math/math.zig");
pub const mem = @import("./src/mem/mem.zig");
pub const typ = @import("./src/typ/typ.zig");

test {
    _ = math;
    _ = mem;
    _ = typ;
}
