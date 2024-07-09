const std = @import("std");

const Atomic = std.atomic.Value;

const Self = @This();

stack_size: usize,
max_threads: usize,

//threads: Atomic(?*Thread) = Atomic(?*Thread).init(null),

const Sync = struct {
    /// Number of threads not searching for Tasks.
    idle: u14 = 0,
    /// Number of threads spawned.
    spawned: u14 = 0,
    unused: bool = false,
    notified: bool = false,
    /// The current state of the thread pool.
    state: enum {
        pending,
        signaled,
        waking,
        shutdown,
    } = .pending,
};

/// Configuration options for the pool.
pub const Config = struct {
    stack_size: usize = (std.Thread.SpawnConfig{}).stack_size,
    max_threads: usize = 0,
};

/// Initialize the thread pool.
pub fn init(config: Config) Self {
    return .{
        .stack_size = config.stack_size,
        .max_threads = config.max_threads orelse std.Thread.getCpuCount() catch 1,
    };
}

/// Wait for a thread to call `shutdown()` on the pool and killt he worker threads.
pub fn deinit(self: *Self) void {
    self.join();
    self.* = undefined;
}

/// A `Task` represents the unit of Work/Job/Execution the pool schedules.
/// User provides `.callback` which is invoked when a thread is ready to run this `Task`.
pub const Task = struct {
    node: Node = .{},
    callback: *const fn (*Task) void,
};

/// An unordered collection of Tasks which can be submitted for scheduling as a group.
pub const Batch = struct {
    len: usize = 0,
    head: ?*Task = null,
    tail: ?*Task = null,

    /// Create a batch from a single task.
    pub fn from(task: *Task) Batch {
        return Batch {
            .len = 1,
            .head = task,
            .tail = task,
        };
    }
};

/// Schedule a batch of tasks to be executed by some thread on the thread pool.
pub fn schedule(self: *Self, batch: Batch) void {
    if (batch.len == 0) return;

    var list = Node.List{

    };
}
