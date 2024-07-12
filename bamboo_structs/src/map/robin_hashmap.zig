//! Inspired by:
//! https://codecapsule.com/2013/11/17/robin-hood-hashing-backward-shift-deletion/

const std = @import("std");

const maple = @import("maple_utils");

const root = @import("./map.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const panic = std.debug.panic;

/// Works well for general purpose key-value storage.
/// Uses 'Robin Hood Hashing' with backward shift deletion.
/// Properties:
/// Low memory, good cache locality, low variance in lookup times.
///
/// complexity |    best     |   average   |    worst    |        factor
/// -----------|-------------|-------------|-------------|----------------------
/// space      | O(n)        | O(n)        | O(Cn)       | grow threshold
/// insertion  | O(1)        | O(1)        | O(n)        | grow routine
/// deletion   | O(1)        | O(1)        | O(n)        | shrink routine
/// lookup     | O(1)        | O(1)        | O(n log n)  | saturation
/// ----------------------------------------------------------------------------
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

        const KV = packed struct {
            key: K = undefined,
            value: V = undefined,
            metadata: u8 = 0,

            // * metadata
            const meta_msk_state: u8 = 0b1000_0000; // (0=empty/1=exist)
            const meta_msk_probe_dist: u8 = 0b0111_1111;

            inline fn isEmpty(kv: *KV) bool {
                return kv.metadata & meta_msk_state == 0;
            }

            inline fn setEmpty(kv: *KV, b: bool) void {
                const mask_b = @as(u8, @intFromBool(b)) -% 1;
                kv.metadata = (kv.metadata & ~meta_msk_state) | (mask_b & meta_msk_state);
            }

            inline fn setProbeDistance(kv: *KV, value: u7) !void {
                kv.metadata = (kv.metadata & ~meta_msk_probe_dist) | (value & meta_msk_probe_dist);
            }

            inline fn getProbeDistance(kv: *KV) u7 {
                return kv.metadata & meta_msk_probe_dist;
            }

            inline fn resetMetadata(kv: *KV) void {
                kv.metadata = 0;
            }
        };

        // struct fields
        kvs: []const KV,
        size: usize = 0,
        size_grow_threshold: usize,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the map, configure with `options`.
        /// After use; release memory by calling 'deinit'.
        pub fn init(options: Options, allocator: Allocator) !Self {
            return @call(.always_inline, initRuntime, .{ options, allocator });
        }

        /// Initialize the map, allocating memory on the heap.
        /// After use; release memory by calling 'deinit'.
        pub fn initRuntime(options: Options, allocator: Allocator) !Self {
            comptime verifyContext(options.ctx);

            // initialize all slots as empty
            const kvs = try allocator.alloc(KV, options.init_capacity);
            for (kvs) |*kv| kv.* = .{}; // KV{} defaults

            // calculate growth threshold
            const tmp_float = @as(f32, @floatFromInt(options.init_capacity)) *| options.grow_threshold;
            const size_grow_threshold = @as(u32, @intFromFloat(tmp_float));

            return .{
                .kvs = kvs,
                .size_grow_threshold = size_grow_threshold,
                .options = options,
                .allocator = allocator,
            };
        }

        /// Initialize the map to work with static space in buffer `buf`.
        /// Ignores `options.init_capacity` and sets `options.growable` to false.
        pub fn initBuffer(buf: []T, options: Options) Self {
            comptime verifyContext(options.ctx);
            return .{

            };
        }

        /// Initialize the map, allocating memory in read-only data or
        /// compiler's address space if not referenced runtime.
        pub fn initComptime(comptime options: Options) !Self {
            if (!@inComptime()) panic("Invalid at runtime.", .{});
            verifyContext(options.ctx);

            // initialize all slots as empty
            const kvs = blk: { // compiler promotes, not 'free-after-use'
                var buf = [_]KV{.{}} ** options.init_capacity;
                break :blk &buf;
            };
            //for (kvs) |*kv| kv.* = .{}; // KV{} defaults

            // calculate growth threshold
            const tmp_float = @as(f32, @floatFromInt(options.init_capacity)) *| options.grow_threshold;
            const size_grow_threshold = @as(u32, @intFromFloat(tmp_float));

            return .{
                .kvs = kvs,
                .size_grow_threshold = size_grow_threshold,
                .ctx = options.ctx,
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
            var probe_dist = 0;

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

                index = (index + 1) % self.kvs.len;
                probe_dist += 1;

                if (probe_dist >= 127) { // overflow, `metadata` has 7-bit probe distance
                    if (self.options.growable) {
                        try self.grow();
                        try self.put(_key, _value);
                    } else {
                        return Error.CapacityReached;
                    }
                }
            }
        }

        /// Remove a `key` - value pair, if successful returns true.
        pub fn remove(self: *Self, key: K) bool {
            const hash = self.options.ctx.hash(key);
            var index = hash % self.kvs.len;
            var probe_dist: u7 = 0;

            while (probe_dist <= self.kvs[index].getProbeDistance()) {
                if (self.options.ctx.eql(self.kvs[index].key, key)) {
                    // found slot with equal key -> remove entry
                    self.backwardShiftDelete(index);
                    return true;
                }
                index = (index + 1) % self.kvs.len;
                probe_dist += 1;
            }
            // `key` was not found
            return false;
        }

        /// Shift backward all the entries _following_ the `index_delete_at` in same bucket.
        /// Leaving the table as if the deleted entry had never been inserted.
        inline fn backwardShiftDelete(self: *Self, index_delete_at: usize) void {
            var index = index_delete_at;
            while (true) {
                const next_index = (index + 1) % self.kvs.len;
                if (self.kvs[next_index].isEmpty() or self.kvs[next_index].getProbeDistance() == 0) {
                    // * next slot has no relation to `index`s bucket,
                    // therefore safe to empty the tail of the shift
                    self.kvs[index].resetMeta();
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
            _ = self;
            _ = key;
        }

        /// Check if map contains the `key`.
        pub fn contains(self: *Self, key: K) bool {
            _ = self;
            _ = key;
        }

        /// Copy over the current content ... having twice the size.
        fn grow() void {}

        /// Calculate threshold 
        inline fn sizeThreshold(size: usize, threshold_percent_float: f64) !u32 {
            if (threshold_percent_float < 0) return error.NegativePercentage;
            std.math.
            const tmp_float = @as(f64, @floatFromInt(size)) *| options.grow_threshold;
            const size_grow_threshold = @as(u32, @intFromFloat(tmp_float));
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
