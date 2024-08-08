//! Author: palsmo

const deque = @import("./double_ended_queue.zig");
const fifo = @import("./fifo_queue.zig");

// exports -->

pub const DoubleEndedQueue = deque.DoubleEndedQueue;
pub const DoubleEndedQueueGeneric = deque.DoubleEndedQueueGeneric;
pub const FifoQueue = fifo.FifoQueue;
pub const FifoQueueGeneric = fifo.FifoQueueGeneric;

// testing -->

test {
    _ = deque;
    _ = fifo;
}
