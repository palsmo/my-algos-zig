//! Author: palsmo
//! Read: https://en.wikipedia.org/wiki/Hash_table
//! Inspiration: https://codecapsule.com/2013/11/17/robin-hood-hashing-backward-shift-deletion/

const std = @import("std");

const maple = @import("maple_utils");

const shared = @import("./shared.zig");

const Allocator = std.mem.Allocator;
const Error = shared.Error;
const mulPercent = maple.math.mulPercent;
const panic = std.debug.panic;
const wrapDecrement = maple.math.wrapDecrement;
const wrapIncrement = maple.math.wrapIncrement;

/// Store key-value pairs of type `K`-key `V`-value.
/// Useful for general purpose key-value storage.
/// Properties:
/// Uses 'Robin Hood Hashing' with backward shift deletion (faster than tombstone).
/// Low memory, good cache locality, low variance in lookup times.
///
/// complexity |     best     |   average    |    worst     |        factor
/// ---------- | ------------ | ------------ | ------------ | ---------------------
/// memory     | O(1)         | O(1)         | O(n)         | grow routine
/// space      | O(n)         | O(n)         | O(2n)        | grow routine
/// insertion  | O(1)         | O(1)         | O(n)         | grow routine
/// deletion   | O(1)         | O(1)         | O(n)         | shrink routine
/// lookup     | O(1)         | O(1)         | O(n log n)   | space saturation
/// -------------------------------------------------------------------------------
pub fn RobinHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        /// Context namespace that can handle most types.
        const default_ctx = struct {
            inline fn eql(a: K, b: K) bool {
                return maple.mem.cmp(a, .eq, b);
            }
            inline fn hash(data: K) bool {
                const bytes = std.mem.asBytes(&data);
                return std.hash.Wyhash.hash(0, bytes);
            }
        };

        pub const Options = struct {
            // initial capacity of the map
            init_capacity: u32 = 100,
            // whether the map can grow beyond `init_capacity`
            growable: bool = true,
            // grow map at this load (75% capacity)
            grow_threshold: f64 = 0.75,
            // namespace containing:
            // eql: fn(a: K, b: K) bool
            // hash: fn(data: K) u64
            comptime ctx: type = default_ctx,
        };

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

        // struct fields
        kvs: []KV,
        comptime kvs_type: enum { Alloc, Buffer, Comptime } = .Alloc, // * for branch pruning in 'grow'
        size: usize = 0,
        size_grow_threshold: ?usize,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the map, configure with `options`.
        /// After use; release memory by calling 'deinit'.
        pub fn init(options: Options, allocator: Allocator) !Self {
            return @call(.always_inline, initAlloc, .{ options, allocator });
        }

        /// Initialize the map, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        pub fn initAlloc(options: Options, allocator: Allocator) !Self {
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});
            comptime verifyContext(options.ctx);

            // * initialize all slots as default
            const kvs = try allocator.alloc(KV, options.init_capacity);
            for (kvs) |*kv| kv.* = .{};

            return .{
                .kvs = kvs,
                .kvs_type = .Alloc,
                .size_grow_threshold = mulPercent(options.grow_threshold, options.init_capacity),
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the map to work with buffer `buf` (* pass undefined memory).
        /// Currently `options` will be ignored.
        pub fn initBuffer(buf: []KV, options: Options) Self {
            if (buf.len) panic("Can't initialize with zero size.", .{});
            comptime verifyContext(options.ctx);

            // * initialize all slots as default
            for (buf) |*kv| kv.* = .{};

            return .{
                .kvs = buf,
                .kvs_type = .Buffer,
                .size_grow_threshold = null,
                .options = options{
                    .init_capacity = buf.len,
                    .growable = false,
                    .grow_threshold = std.math.nan(f64),
                },
                .allocator = null,
            };
        }

        /// Initialize the map, allocating memory in read-only data or
        /// compiler's address space if not referenced runtime.
        pub fn initComptime(comptime options: Options) !Self {
            if (!@inComptime()) panic("Invalid at runtime.", .{});
            if (options.init_capacity == 0) panic("Can't initialize with zero size.", .{});
            verifyContext(options.ctx);

            // * initialize all slots as default
            const kvs = blk: { // compiler promotes, not 'free-after-use'
                var buf = [_]KV{.{}} ** options.init_capacity;
                break :blk &buf;
            };

            return .{
                .kvs = kvs,
                .kvs_type = .Comptime,
                .size_grow_threshold = mulPercent(options.grow_threshold, options.init_capacity),
                .options = options,
                .allocator = null,
            };
        }

        /// Release allocated memory, cleanup routine for 'init'.
        pub fn deinit(self: *Self) void {
            if (self.allocator) |ally| {
                ally.free(self.stack);
            } else {
                panic("Can't deallocate with `null` allocator.", .{});
            }
        }

        /// Store a `key` - `value` pair.
        pub fn put(self: *Self, key: K, value: V) !void {
            if (self.size >= self.size_grow_threshold) {
                if (self.options.growable) try self.grow() else return Error.CapacityReached;
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

        /// Remove a `key` - value pair, if successful returns true.
        pub fn remove(self: *Self, key: K) bool {
            if (self.size == 0) return true;

            const hash = self.options.ctx.hash(key);
            var index = hash % self.kvs.len;
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

        /// Get a copy of a value with `key`, returns 'null' if non-existent.
        pub fn get(self: *Self, key: K) ?V {
            if (self.size == 0) return null;

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

        /// Check if map contains the `key`.
        pub fn contains(self: *Self, key: K) bool {
            if (self.size == 0) return false;

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
        fn grow(self: *Self) void {
            // allocate buffer with more capacity
            const new_capacity = self.kvs.len * 2;
            const new_buffer = switch (self.typ) {
                .Alloc => try self.allocator.?.alloc(KV, new_capacity),
                .Buffer => unreachable,
                .Comptime => blk: { // compiler promotes, not 'free-after-use'
                    if (!@inComptime()) panic("Can't grow comptime buffer at runtime.", .{});
                    var buf: [new_capacity]KV = undefined;
                    break :blk &buf;
                },
            };

            const old_mem = self.kvs[0..self.size];
            const new_mem = new_buffer[0..self.size];
            @memcpy(new_mem, old_mem);
            for (new_mem[self.size..]) |*slot| slot.* = KV{}; // initialize slack slots as default

            if (self.kvs_type == .Alloc) self.allocator.?.free(self.kvs);

            self.kvs = new_buffer;
            self.size_grow_threshold = mulPercent(self.options.grow_threshold, new_capacity);
        }

        /// Verify properties of `Ctx`.
        fn verifyContext(comptime Ctx: type) void {
            if (@typeInfo(Ctx) != .Struct) {
                @compileError("Expected struct, found '" ++ @typeName(Ctx) ++ "'.");
            }

            const decls = .{
                .{ "eql", .{ K, K }, bool },
                .{ "hash", .{K}, u64 },
            };

            inline for (decls) |decl| {
                const name = decl[0];
                const in_types = decl[1];
                const out_type = decl[2];
                if (!@hasDecl(Ctx, name)) {
                    @compileError("Expected declaration by name '" ++ name ++ "' in `Ctx` argument.");
                }
                const fn_type = @field(Ctx, name);
                maple.typ.assertFn(fn_type, in_types, out_type);
            }
        }
    };
}
