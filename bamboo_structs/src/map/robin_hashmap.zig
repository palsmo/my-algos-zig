//! Author: palsmo
//! Status: In Progress
//! Read: https://en.wikipedia.org/wiki/Hash_table
//! Inspiration: https://codecapsule.com/2013/11/17/robin-hood-hashing-backward-shift-deletion/

const std = @import("std");

const maple = @import("maple_utils");

const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const Error = shared.Error;
const assertAndMsg = maple.debug.assertAndMsg;
const assertPowOf2 = maple.math.assertPowOf2;
const fastMod = maple.math.fastMod;
const mulPercent = maple.math.mulPercent;
const panic = std.debug.panic;
const verifyContext = maple.typ.verifyContext;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// A hashed map for key-value pairs of type `K` and `V`.
/// Useful for general purpose key-value storage.
/// Provides efficient insertion, removal and lookup operations for keys.
///
/// Reference to 'self.kvs' may become invalidated after grow/shrink routine,
/// use 'self.isValidRef' to verify.
///
/// Properties:
/// Uses 'Robin Hood Hashing' with backward shift deletion (generally faster than tombstone).
///
///  complexity |     best     |   average    |    worst     |        factor
/// ------------|--------------|--------------| -------------|----------------------
/// memory idle | O(n)         | O(n)         | O(4n)        | grow/shrink routine
/// memory work | O(1)         | O(1)         | O(2)         | grow/shrink routine
/// insertion   | O(1)         | O(1)         | O(n)         | grow routine
/// deletion    | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup      | O(1)         | O(1)         | O(n log n)   | space saturation
/// ------------|--------------|--------------|--------------|----------------------
///  cache loc  | decent       | decent       | decent       | hash-spread
/// --------------------------------------------------------------------------------
pub fn RobinHashMap(comptime K: type, comptime V: type) type {
    return struct {
        pub const Options = struct {
            // initial capacity of the map, asserted to be a power of 2 (efficiency reasons)
            init_capacity: u32 = 64,
            // whether the map can grow beyond `init_capacity`
            growable: bool = true,
            // grow map at this load (75% capacity)
            grow_threshold: ?f64 = 0.75,
            // whether the map can shrink when grown past `init_capacity`,
            // will half when size used falls below 1/4 of capacity
            shrinkable: bool = true,
            // namespace containing:
            // eql: fn(a: K, b: K) bool
            // hash: fn(data: K) u64
            comptime ctx: type = default_ctx,
        };

        /// Context namespace used by default that can handle most types.
        const default_ctx = struct {
            inline fn eql(a: K, b: K) bool {
                return maple.mem.cmp(a, .eq, b);
            }
            inline fn hash(data: K) bool {
                const bytes = std.mem.asBytes(&data);
                return std.hash.Wyhash.hash(0, bytes);
            }
        };

        /// Key-Value (slot) memory layout in map.
        pub const KV = packed struct {
            key: K = undefined,
            value: V = undefined,
            metadata: u8 = 0,

            // * metadata
            const meta_msk_state: u8 = 0b1000_0000; // (0=empty/1=exist)
            const meta_msk_probe_dist: u8 = 0b0111_1111;

            pub inline fn isEmpty(kv: *KV) bool {
                return kv.metadata & meta_msk_state == 0;
            }

            pub inline fn setEmpty(kv: *KV, b: bool) void {
                const mask_b = @as(u8, @intFromBool(b)) -% 1;
                kv.metadata = (kv.metadata & ~meta_msk_state) | (mask_b & meta_msk_state);
            }

            pub inline fn setProbeDistance(kv: *KV, value: u8) !void {
                kv.metadata = (kv.metadata & ~meta_msk_probe_dist) | (value & meta_msk_probe_dist);
            }

            pub inline fn getProbeDistance(kv: *KV) u8 {
                return kv.metadata & meta_msk_probe_dist;
            }

            pub inline fn resetMetadata(kv: *KV) void {
                kv.metadata = 0;
            }
        };

        /// Initialize the queue, allocating memory on the heap.
        /// User should release memory after use by calling 'deinit'.
        /// Function is valid only during _runtime_.
        pub fn initAlloc(options: Options, allocator: Allocator) !RobinHashMapGeneric(K, V, .Alloc) {
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertAndMsg(options.grow_threshold >= 0.0 and options.grow_threshold <= 1.0, "Growth-threshold has to be between 0.0 and 1.0", .{});
            assertPowOf2(options.init_capacity);

            comptime verifyContext(options.ctx);

            return .{
                .kvs = b: {
                    const buf = try allocator.?.alloc(KV, options.init_capacity);
                    for (buf) |*slot| slot.* = .{}; // * init all slots as default
                    break :b buf;
                },
                .size_grow_threshold = mulPercent(options.grow_threshold, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the queue to work with static space in buffer `buf`.
        /// Fields in `options` that will be ignored are; init_capacity, growable, grow_threshold, shrinkable.
        /// Function is valid during _comptime_ or _runtime_.
        pub fn initBuffer(buf: []KV, options: Options) RobinHashMapGeneric(K, V, .Buffer) {
            assertAndMsg(buf.len > 0, "Can't initialize with zero size.", .{});
            assertAndMsg(options.grow_threshold >= 0.0 and options.grow_threshold <= 1.0, "Growth-threshold has to be between 0.0 and 1.0", .{});
            assertPowOf2(buf.len);

            comptime verifyContext(options.ctx);

            return .{
                .kvs = b: {
                    for (buf) |*slot| slot.* = .{};
                    break :b buf;
                },
                .size_grow_threshold = null,
                .options = options{
                    .init_capacity = buf.len,
                    .growable = false,
                    .grow_threshold = null,
                    .shrinkable = false,
                },
                .allocator = null,
            };
        }

        /// Initialize the queue, allocating memory in .rodata or
        /// compiler's address space if not referenced runtime.
        /// Function is valid during _comptime_.
        pub fn initComptime(comptime options: Options) RobinHashMapGeneric(K, V, .Comptime) {
            assertAndMsg(@inComptime(), "Invalid at runtime.", .{});
            assertAndMsg(options.init_capacity > 0, "Can't initialize with zero size.", .{});
            assertAndMsg(options.grow_threshold >= 0.0 and options.grow_threshold <= 1.0, "Growth-threshold has to be between 0.0 and 1.0", .{});
            assertPowOf2(options.init_capacity);

            comptime verifyContext(options.ctx);

            return .{
                .kvs = undefined,
                .size_grow_threshold = mulPercent(options.grow_threshold, options.init_capacity),
                .options = options,
                .allocator = null,
            };
        }
    };
}

/// Digest of some 'RobinHashMap' init-function.
/// Depending on `buffer_type` certain operations may be pruned or optimized comptime.
pub fn RobinHashMapGeneric(comptime K: type, comptime V: type, comptime buffer_type: enum { Alloc, Buffer, Comptime }) type {
    return struct {
        const Self = @This();

        const Robin = RobinHashMap(K, V);

        // struct fields
        kvs: Robin.KV,
        size: usize = 0,
        size_grow_threshold: ?usize,
        options: Robin.Options,
        allocator: ?Allocator,

        /// Release allocated memory, cleanup routine for 'initAlloc'.
        pub fn deinit(self: *Self) void {
            switch (buffer_type) {
                .Alloc => self.allocator.?.free(self.buffer),
                .Buffer, .Comptime => panic("Can't deallocate with nonexistent allocator.", .{}),
            }
        }

        /// Store a `key` - `value` pair in the map.
        pub fn put(self: *Self, key: K, value: V) !void {
            // grow?
            if (self.size < self.buffer.len) {} else {
                switch (buffer_type) {
                    .Alloc => if (self.options.growable) try self.grow() else return Error.Overflow,
                    .Buffer => return Error.Overflow,
                    .Comptime => {
                        assertAndMsg(@inComptime(), "Invalid at runtime.", .{});
                        if (self.options.growable) try self.grow() else return Error.Overflow;
                    },
                }
            }

            const hash = self.options.ctx.hash(key);
            var index = hash % self.kvs.len;
            var _key = key;
            var _value = value;
            var probe_dist: u8 = 0;

            while (true) {
                if (self.kvs[index].isEmpty()) {
                    // found empty slot -> put `key`
                    self.kvs[index].key = _key;
                    self.kvs[index].value = _value;
                    self.kvs[index].setEmpty(false);
                    self.size += 1;
                    return;
                }
                if (self.options.ctx.eql(self.kvs[index].key, _key)) {
                    // found slot with equal key -> update with `value`
                    self.kvs[index].value = value;
                    return;
                }
                if (self.kvs[index].getProbeDistance() < probe_dist) {
                    // * steal from the rich, give to the poor (lower is richer)
                    const tmp = self.kvs[index];
                    self.kvs[index].key = _key;
                    self.kvs[index].value = _value;
                    try self.kvs[index].setProbeDistance(probe_dist);
                    _key = tmp.key;
                    _value = tmp.value;
                    probe_dist = tmp.getProbeDistance();
                }

                index = wrapIncrement(usize, index, 0, self.kvs.len);
                probe_dist += 1;

                // probe distance in `self.metadata` is stored in 7 bits
                if (probe_dist < 128) {} else return Error.ProbeDistanceOverflow;
            }
        }

        /// Remove a `key` - value pair from the map.
        /// Returns true (success) or false (fail).
        pub fn remove(self: *Self, key: K) bool {
            if (self.size != 0) {} else return true;

            const hash = self.options.ctx.hash(key);
            var index = fastMod(hash, self.kvs.len);
            var probe_dist: u8 = 0;

            while (probe_dist <= self.kvs[index].getProbeDistance()) {
                if (self.options.ctx.eql(self.kvs[index].key, key)) {
                    // found slot with equal key -> remove entry
                    self.backwardShiftDelete(index);
                    return true;
                }

                index = wrapIncrement(usize, index, self.kvs.len);
                probe_dist += 1;

                // probe distance in `self.metadata` is stored in 7 bits
                if (probe_dist < 128) {} else return Error.ProbeDistanceOverflow;
            }

            // `key` was not found
            return false;
        }

        /// Shift backward all the entries _following_ the `index_delete_at` in same bucket.
        /// Leaving the table as if the deleted entry had never been inserted.
        inline fn backwardShiftDelete(self: *Self, index_delete_at: usize) void {
            var index = index_delete_at;
            while (true) {
                const next_index = wrapIncrement(usize, index, self.kvs.len);

                if (self.kvs[next_index].isEmpty() or self.kvs[next_index].getProbeDistance() == 0) {
                    // * next slot has no relation to `index`s bucket,
                    // therefore safe to empty the tail of the shift
                    self.kvs[index].resetMetadata();
                    self.size -= 1;
                    return;
                }

                // shift the next element back
                self.kvs[index] = self.kvs[next_index];
                self.kvs[index].setProbeDistance(self.kvs[next_index].getProbeDistance() - 1);
                index = next_index;
            }
        }

        /// Get from `key` the associated value from the map.
        /// Returns _null_ only if there's no value.
        /// This function may throw error but chances are miniscule.
        pub fn get(self: *Self, key: K) !?V {
            if (self.size != 0) {} else return null;

            const hash = self.options.ctx.hash(key);
            var index = hash % self.kvs.len;
            var probe_dist: u8 = 0;

            while (probe_dist <= self.kvs[index].getProbeDistance()) {
                if (self.options.ctx.eql(self.kvs[index].key, key)) {
                    // found slot with equal key -> return value
                    return self.kvs[index].value;
                }

                index = wrapIncrement(usize, index, 0, self.kvs.len);
                probe_dist += 1;

                // probe distance in `self.metadata` is stored in 7 bits
                if (probe_dist < 128) {} else return Error.ProbeDistanceOverflow;
            }

            // `key` was not found
            return null;
        }

        /// Check if `key` is a member of the map.
        /// Returns _true_ (found) or _false_ (not found).
        pub fn contains(self: *Self, key: K) bool {
            if (self.size != 0) {} else return false;

            const hash = self.options.ctx.hash(key);
            var index = hash % self.kvs.len;
            var probe_dist: u8 = 0;

            while (probe_dist <= self.kvs[index].getProbeDistance()) {
                if (self.options.ctx.eql(self.kvs[index].key, key)) {
                    // found slot with equal key -> return true
                    return true;
                }

                index = wrapIncrement(usize, index, 0, self.kvs.len);
                probe_dist += 1;

                // probe distance in `self.metadata` is stored in 7 bits
                if (probe_dist < 128) {} else return Error.ProbeDistanceOverflow;
            }

            // `key` was not found
            return false;
        }
        /// Copy over current key-value pairs into new buffer of twice the size.
        /// This function may throw error as part of the allocation process.
        fn grow(self: *Self) void {
            // allocate new buffer with more capacity
            const new_capacity = self.kvs.len * 2;
            const new_buffer = switch (self.typ) {
                .Alloc => try self.allocator.?.alloc(Robin.KV, new_capacity),
                .Buffer => unreachable,
                .Comptime => blk: { // compiler promotes, not 'free-after-use'
                    assertAndMsg(@inComptime(), "Can't grow comptime buffer at runtime.", .{});
                    var buf: [new_capacity]Robin.KV = undefined;
                    break :blk &buf;
                },
            };

            const old_mem = self.kvs[0..self.size];
            const new_mem = new_buffer[0..self.size];
            @memcpy(new_mem, old_mem);
            for (new_mem[self.size..]) |*slot| slot.* = .{}; // initialize slack slots as default

            if (buffer_type == .Alloc) self.allocator.?.free(self.kvs);

            self.kvs = new_buffer;
            self.size_grow_threshold = mulPercent(self.options.grow_threshold, new_capacity);
        }

        /// Verify properties of `ctx`.
        fn verifyContext(comptime ctx: type) void {
            if (@typeInfo(ctx) != .Struct) {
                @compileError("Expected struct, found '" ++ @typeName(ctx) ++ "'.");
            }

            const decls = .{
                .{ "eql", .{ K, K }, bool },
                .{ "hash", .{K}, u64 },
            };

            inline for (decls) |decl| {
                const name = decl[0];
                const in_types = decl[1];
                const out_type = decl[2];
                if (!@hasDecl(ctx, name)) {
                    @compileError("Expected declaration by name '" ++ name ++ "' in `ctx` argument.");
                }
                const fn_type = @field(ctx, name);
                maple.typ.assertFn(fn_type, in_types, out_type);
            }
        }
    };
}
