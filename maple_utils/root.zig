pub const math = @import("./src/math/root.zig");
pub const mem = @import("./src/mem/root.zig");
pub const typ = @import("./src/typ/root.zig");

test {
    _ = math;
    _ = mem;
    _ = typ;
}
