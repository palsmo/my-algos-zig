const std = @import("std");

const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const Thread = std.Thread;

const Task = struct {
    function: *const fn () void,
};

const Self = @This();

threads: []Thread,
task_queue: Queue(Task),
should_stop: Atomic(bool),

pub fn init(thread_count: usize, allocator: Allocator) !Self {
    var pool = Self{
        .threads = try allocator.alloc(Thread, thread_count),
        .task_queue = Queue(Task).init(),
        .should_stop = Atomic(bool).init(false),
    };

    for (pool.threads) |*thread| {
        thread.* = try Thread.spawn(config: SpawnConfig, comptime function: anytype, args: anytype)
    }
}
