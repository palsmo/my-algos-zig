//! Author: palsmo
//! Status: In Progress
//! About: Single Linked List Data Structure
//! Read: https://en.wikipedia.org/wiki/Linked_list

const std = @import("std");

const maple = @import("maple_utils");

const mod_shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;

/// A single linked list for items of type `T`.
pub fn SingleLinkedList(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        pub const Options = struct {
            // initial capacity of the list
            init_capacity: usize = 32,
            // whether the list can auto grow beyond `init_capacity`
            growable: bool = true,
            // whether the list can auto shrink when grown past `init_capacity`,
            // size will half when used space falls bellow 1/4 of capacity
            shrinkable: bool = true,
        };

        pub const Node = struct {
            data: T,
            next: ?*Node,

            pub fn init(data: T) Node {
                return .{
                    .data = data,
                    .next = null,
                };
            }
        };

        // struct fields
        head: ?*Node,
        options: Options,
        allocator: ?std.mem.Allocator,

        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
        };

        /// Initialize the list for using heap allocation.
        inline fn initAlloc(allocator: Allocator, comptime options: Options) Self {
            return .{
                .head = null,
                .options = options,
                .allocator = allocator,
            };
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Alloc => {
                    assertAndMsg(self.allocator != null, "Passed allocator was unexpectedly 'null'.", .{});
                    const ally = self.allocator orelse unreachable;
                    ally.free(self.buffer);
                },
                else => unreachable,
            }
        }

        /// Store an `item` last in the list.
        /// Issue key specs:
        /// - Throws error on failed allocation process (only *.Alloc* `memory_mode`).
        pub fn append(self: *Self, data: T) !void {
            const new_node = switch (memory_mode) {
                .Alloc => {
                    try self.allocator.create(Node);
                },
                else => unreachable,
            };

            new_node.* = Node.init(data);

            if (self.head) |head| {
                var current = head;
                while (current) |_current| {
                    current = _current.next;
                } else {
                    current = new_node;
                }
            } else {
                self.head = new_node;
            }
        }
    };
}
