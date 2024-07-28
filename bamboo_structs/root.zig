//pub const map = @import("./src/map/map.zig");
pub const queue = @import("./src/queue/root.zig");
//pub const stack = @import("./src/stack/stack.zig");
pub const shared = @import("./src/shared.zig");

test {
    //_ = map;
    _ = queue;
    //_ = stack;
    _ = shared;
}
