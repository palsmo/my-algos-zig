//! Author: palsmo
//! Status: In Progress

const std = @import("std");

const maple = @import("maple_utils");

const Allocator = std.mem.Allollocator;
const FifoQueue = maple.queue.FifoQueue;
const FifoQueueGeneric = maple.queue.FifoQueueGeneric;

pub const KeyCode = enum(u8) {
    A = 65,
    B = 66,
    Escape = 27,
};

pub const KeyEvent = struct {
    key_code: u32,
    is_pressed: bool,
};

pub const KeyboardHandler = struct {
    const Self = @This();

    pub const Options = struct {};

    // struct fields
    key_press_states: [256]bool = .{false} ** 256,
    key_event_queue: FifoQueueGeneric(KeyEvent),
    allocator: Allocator,

    /// Initialize the handler, any memory allocation is done on the heap.
    /// User should release memory after use by calling 'deinit'.
    /// Function is valid only during _runtime_.
    pub fn init(allocator: Allocator, options: Options) !Self {
        _ = options;
        return .{
            .state = .{},
            .event_queue = try FifoQueue(KeyEvent).initAlloc(allocator, .{
                .init_capacity = 64,
                .growable = false,
                .shrinkable = false,
            }),
        };
    }

    /// Release allocated memory, cleanup routine for 'init'.
    pub fn deinit(self: *Self) void {
        self.key_event_queue.deinit();
    }

    /// Detect any key event currently happening on the system.
    pub fn pollKeyEvents(self: *Self) !void {
        _ = self;
        // TODO, detect key event from different platforms,
        // create a KeyEvent and add it to the 'event_queue'
    }

    /// Periodically call this function to handle queued events.
    pub fn processKeyEventQueue(self: *Self) void {
        _ = self;
        // TODO, iterate through 'event_queue'
        // allowing the application to respond to each key press or release.
    }

    /// Fast check if `key_code` is currently pressed down.
    pub fn isPressed(self: *const Self, comptime key_code: KeyCode) bool {
        return self.state.keys[@intFromEnum(key_code)];
    }
};

test KeyboardHandler {
    const allocator = std.testing.allocator;
    const keyboard_handler = KeyboardHandler.init(allocator, .{});
    _ = keyboard_handler;
}
