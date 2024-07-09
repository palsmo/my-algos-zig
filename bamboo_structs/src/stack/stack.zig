const byted = @import("./byte_stack.zig");

// exports -->

pub const ByteStack = byted.ByteStack;

pub const Error = error{
    Overflow,
    Underflow,
};

// testing -->

test {
    _ = byted;
}
