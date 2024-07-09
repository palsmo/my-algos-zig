const fifo = @import("./fifo_queue.zig");

// exports -->

pub const FifoQueue = fifo.FifoQueue;

pub const Error = error{
    Overflow,
    Underflow,
};

// testing -->

test {
    _ = fifo;
}
