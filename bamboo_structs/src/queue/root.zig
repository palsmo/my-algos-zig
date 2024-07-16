const deque = @import("./double_ended_queue.zig");
//const fifo = @import("./fifo_queue.zig");
const shared = @import("./shared.zig");

// exports -->

pub const DoubleEndedQueue = deque.DoubleEndedQueue;
//pub const FifoQueue = fifo.FifoQueue;
pub const Error = shared.Error;

// testing -->

test {
    _ = deque;
    //_ = fifo;
}