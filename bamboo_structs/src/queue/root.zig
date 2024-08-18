//! Author: palsmo
//! Status: Done
//! About: Root File Queue Functionality

const root_deque = @import("./double_ended_queue.zig");
const root_fifo = @import("./fifo_queue.zig");

// exports -->

pub const misc = struct {
    pub const DoubleEndedQueue = root_deque.DoubleEndedQueue;
    pub const DoubleEndedQueueGeneric = root_deque.DoubleEndedQueueGeneric;
    pub const FifoQueue = root_fifo.FifoQueue;
    pub const FifoQueueGeneric = root_fifo.FifoQueueGeneric;
};

// testing -->

test {
    _ = root_deque;
    _ = root_fifo;
}
