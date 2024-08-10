//! Author: palsmo
//! Status: In Progress
//! About: Single Linked List Data Structure
//! Read: https://en.wikipedia.org/wiki/Linked_list

const std = @import("std");

const maple = @import("maple_utils");

const mod_shared = @import("../shared.zig");

const Allocator = std.mem.Allocator;
const ExecMode = mod_shared.ExecMode;
const BufferError = mod_shared.BufferError;
const MemoryMode = mod_shared.MemoryMode;
const assertAndMsg = maple.assert.assertAndMsg;
const assertComptime = maple.assert.assertComptime;
const panic = std.debug.panic;

/// A forward traversal linked list for items of type `T`.
/// Useful for ...
/// Worse for ...
///
/// Depending on `memory_mode` certain operations may be pruned or optimized comptime.
///
/// Properties:
/// Uses 'Sentinel Node' for list bounds (fast and memory efficient).
///
///  complexity |     best     |   average    |    worst     |                factor
/// ------------|--------------|--------------|--------------|--------------------------------------
/// insertion   | O(1)         | O(1)         | O(1)         | -
/// deletion    | O(1)         | O(1)         | O(1)         | -
/// lookup      | O(1)         | O(n)         | O(n)         | -
/// ------------|--------------|--------------|--------------|--------------------------------------
/// memory idle | O(n)         | O(n)         | O(n)         | -
/// memory work | O(1)         | O(1)         | O(1)         | -
/// ------------|--------------|--------------|--------------|--------------------------------------
///  cache loc  | decent       | decent       | poor         | memory allocations
/// ------------------------------------------------------------------------------------------------
pub fn SingleLinkedList(comptime T: type, comptime memory_mode: MemoryMode) type {
    return struct {
        const Self = @This();

        // Memory unit linked to consequent units to form the list.
        pub const Node = struct {
            data: T,
            next: *Node,

            pub fn init(data: T, next: *Node) Node {
                return .{
                    .data = data,
                    .next = next,
                };
            }
        };

        // struct fields
        sentinel: Node, // sentinel -> (first) -> ... -> (last) -> sentinel
        tail: *Node,
        size: usize = 0,
        allocator: ?std.mem.Allocator,
        buffer: ?[]Node,

        /// Initialize the list with the active `memory_mode` branch (read more *MemoryMode*).
        ///
        ///    mode   |                                    about
        /// ----------|-----------------------------------------------------------------------------
        /// .Alloc    | fn (allocator: Allocator, comptime options: Options) !Self
        /// .Buffer   | fn (buf: []T, comptime options: Options) Self
        /// .Comptime | fn (comptime options: Options) Self
        /// ----------------------------------------------------------------------------------------
        pub const init = switch (memory_mode) {
            .Alloc => initAlloc,
            .Buffer => initBuffer,
            .Comptime => initComptime,
        };

        /// Initialize the list for using heap allocation.
        inline fn initAlloc(allocator: Allocator) Self {
            var self = Self{
                .sentinel = Node{ .data = undefined, .next = undefined },
                .tail = undefined,
                .allocator = allocator,
                .buffer = null,
            };

            // make sentinel node and tail point to sentinel node
            self.sentinel.next = &self.sentinel;
            self.tail = &self.sentinel;

            return self;
        }

        /// Initialize the list for working with user provided `buf`.
        /// Issue key specs:
        /// - Panics when 'buf.len' is zero.
        inline fn initBuffer(buf: []Node) Self {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});

            var self = Self{
                .sentinel = Node{ .data = undefined, .next = undefined },
                .tail = undefined,
                .allocator = null,
                .buffer = buf,
            };

            // make sentinel node and tail point to sentinel node
            self.sentinel.next = &self.sentinel;
            self.tail = &self.sentinel;

            return self;
        }

        /// Initialize the list for using comptime memory allocation.
        inline fn initComptime() Self {
            assertComptime(@src().fn_name);

            var self = Self{
                .sentinel = Node{ .data = undefined, .next = undefined },
                .tail = undefined,
                .allocator = null,
                .buffer = null,
            };

            // make sentinel node and tail point to sentinel node
            self.sentinel.next = &self.sentinel;
            self.tail = &self.sentinel;

            return self;
        }

        /// Release allocated memory, cleanup routine.
        pub fn deinit(self: *const Self) void {
            switch (memory_mode) {
                .Alloc => {
                    const ally = self.allocator orelse unreachable;
                    var current: Node = self.sentinel.next;
                    while (current != &self.sentinel) {
                        const next = current.next;
                        ally.destroy(current);
                        current = next;
                    }
                },
                .Buffer, .Comptime => {
                    @compileError("Can't release, list is not allocated on the heap (remove call 'deinit').");
                },
            }
        }

        /// Store an `item` first in the list.
        /// Issue key specs:
        /// - Throws error when resize allocation fail (only *.Alloc* `memory_mode`).
        pub fn pushFirst(self: *Self, item: T) !void {
            // allocate memory for new node
            const ptr_new_node = switch (memory_mode) {
                .Alloc => b: {
                    const ally = self.allocator orelse unreachable;
                    break :b try ally.create(Node);
                },
                .Buffer => b: {
                    const buf = self.buffer orelse unreachable;
                    if (self.size < buf.len) {} else return BufferError.Overflow;
                    break :b &buf[self.size];
                },
                .Comptime => b: { // * not free-after-use, compiler promotes
                    var node: Node = undefined;
                    break :b &node;
                },
            };

            ptr_new_node.* = Node.init(item, &self.sentinel);

            self.sentinel.next = ptr_new_node;
            if (self.size == 0) self.tail = ptr_new_node;
            self.size += 1;
        }

        /// Store an `item` last in the list.
        /// Issue key specs:
        /// - Throws error when resize allocation fail (only *.Alloc* `memory_mode`).
        pub fn pushLast(self: *Self, item: T) !void {
            // allocate memory for new node
            const ptr_new_node = switch (memory_mode) {
                .Alloc => b: {
                    const ally = self.allocator orelse unreachable;
                    break :b try ally.create(Node);
                },
                .Buffer => b: {
                    const buf = self.buffer orelse unreachable;
                    if (self.size < buf.len) {} else return BufferError.Overflow;
                    break :b &buf[self.size];
                },
                .Comptime => b: { // * not free-after-use, compiler promotes
                    var node: Node = undefined;
                    break :b &node;
                },
            };

            ptr_new_node.* = Node.init(item, &self.sentinel);

            // update last node link, replace tail reference
            self.tail.next = ptr_new_node;
            self.tail = ptr_new_node;
            self.size += 1;
        }

        /// Get the first item in the list, free its memory.
        ///  complexity |                                   about
        /// ------------|---------------------------------------------------------------------------
        /// O(1)        | sentinel_node -> first_node, sentinel_node -> second_node (<- first_node)
        /// ----------------------------------------------------------------------------------------
        pub fn popFirst(self: *Self, comptime exec_mode: ExecMode) ?T {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            // check empty
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (self.size != 0) {} else return null,
            }

            const ref_first_node = self.sentinel.next;
            self.sentinel.next = ref_first_node.next;
            const data = ref_first_node.data;

            switch (memory_mode) {
                .Alloc => {
                    const ally = self.allocator orelse unreachable;
                    ally.destroy(ref_first_node);
                },
                .Buffer => {},
                .Comptime => {},
            }

            return data;
        }

        /// Get the last item in the list, free its memory.
        ///  complexity |                                   about
        /// ------------|---------------------------------------------------------------------------
        /// O(n)        | traverse nodes until second-to-last, make that tail and return prev tail
        /// ----------------------------------------------------------------------------------------
        pub fn popLast(self: *Self, comptime exec_mode: ExecMode) ?T {
            if (memory_mode == .Comptime) assertComptime(@src().fn_name);

            // check empty
            switch (exec_mode) {
                .Uncheck => {}, // TODO! Add logging in verbose mode to warn about this.
                .Safe => if (self.size != 0) {} else return null,
            }

            var result: T = undefined;

            if (self.size == 1) {
                result = self.sentinel.next.data;
            } else {
                // traverse nodes until second-to-last node
                var ref_current = self.sentinel.next;
                while (ref_current.next != self.tail) {
                    ref_current = ref_current.next;
                }
                result = self.tail.data;
                ref_current.next = &self.sentinel;
                self.tail = ref_current;
            }

            switch (memory_mode) {
                .Alloc => {
                    const ally = self.allocator orelse unreachable;
                    ally.destroy(self.tail.next);
                },
                .Buffer, .Comptime => {},
            }

            self.size -= 1;
            return result;
        }

        /// Reset the list to its empty initial state.
        pub fn reset(self: *Self) void {
            switch (memory_mode) {
                .Alloc => {
                    // traverse nodes and release their memory
                    const ally = self.allocator orelse unreachable;
                    var ref_current = self.sentinel.next;
                    while (ref_current != &self.sentinel) {
                        const ref_next = ref_current.next;
                        ally.destroy(ref_current);
                        ref_current = ref_next;
                    }
                },
                .Buffer, .Comptime => {},
            }

            self.sentinel.next = &self.sentinel;
            self.tail = &self.sentinel;
            self.size = 0;
        }
    };
}
