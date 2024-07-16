pub const debug = @import("./src/debug/root.zig");
pub const math = @import("./src/math/root.zig");
pub const mem = @import("./src/mem/root.zig");
pub const typ = @import("./src/typ/root.zig");

test {
    _ = debug;
    _ = math;
    _ = mem;
    _ = typ;
}
