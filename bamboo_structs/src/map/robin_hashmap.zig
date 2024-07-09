//! Inspired by:
//! https://codecapsule.com/2013/11/17/robin-hood-hashing-backward-shift-deletion/

const std = @import("std");

const maple = @import("maple_utils");

const root = @import("./map.zig");

const Allocator = std.mem.Allocator;
const Error = root.Error;
const panic = std.debug.panic;

/// Works well for general-purpose usage.
/// Uses 'Robin Hood Hashing' with backward shift deletion.
pub fn RobinHashMap(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        // Namespace with some contexts.
        const context = struct {
            const bytes = struct {
                inline fn eql(a: []const u8, b: []const u8) bool {
                    return @call(.always_inline, std.mem.eql, .{ u8, a, b });
                }
                inline fn hash(data: []const u8) u64 {
                    return std.hash.Wyhash.hash(0, data);
                }
            };
            const numeric = struct {
                inline fn eql(a: K, b: K) bool {
                    switch (@typeInfo(K)) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => return a == b,
                        else => @compileError("Expected numeric, found " ++ @typeName(K)),
                    }
                }
                inline fn hash(data: K) u64 {
                    switch (@typeInfo(K)) {
                        .Int, .Float, .ComptimeInt, .ComptimeFloat => {
                            return std.hash.Wyhash.hash(0, std.mem.asBytes(data));
                        },
                        else => @compileError("Expected numeric, found " ++ @typeName(K)),
                    }
                }
            };
        };

        pub const Options = struct {
            // initial capacity of the hash map
            init_capacity: u32 = 100,
            // whether the hash map can grow beyond its initial capacity
            growable: bool = true,
            // grow hashmap at this load (75% capacity)
            grow_threshold: f32 = 0.75,
            // namespace containing:
            // eql: fn(a: K, b: K) bool
            // hash: fn(data: K) u64
            comptime ctx: type = context.bytes,
        };

        const KV = packed struct {
            key: K = undefined,
            value: V = undefined,
            metadata: u8 = 0, // status empty, zero probe distance

            // 7th bit for state (empty=0/exist=1), rest for probe distance
            const mask_state: u8 = 1 << 7;
            const mask_probe_dist: u8 = ~mask_state;

            inline fn resetMetadata(kv: *KV) void {
                kv.metadata = 0;
            }

            inline fn isEmpty(kv: *KV) bool {
                return kv.metadata & mask_state == 0;
            }

            inline fn setEmpty(kv: *KV, b: bool) void {
                const mask_b = @as(u8, @intFromBool(b)) -% 1;
                kv.metadata = (kv.metadata & ~mask_state) | (mask_b & mask_state);
            }

            inline fn setProbeDistance(kv: *KV, value: u7) void {
                kv.metadata = (kv.metadata & ~mask_probe_dist) | (value & mask_probe_dist);
            }

            inline fn getProbeDistance(kv: *KV) u7 {
                return kv.metadata & mask_probe_dist;
            }
        };

        // struct fields
        kvs: []const KV,
        size: usize = 0,
        size_grow_threshold: usize,
        options: Options,
        allocator: ?Allocator,

        /// Initialize the hashmap, configure with `options`.
        /// After use; release memory by calling 'deinit'.
        pub fn init(options: Options, allocator: Allocator) !Self {
            return @call(.always_inline, initRuntime, .{ options, allocator });
        }

        /// Initialize the hashmap, allocating memory on the heap.
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

        /// Initialize the hashmap for comptime usage.
        /// Allocating memory in read-only data.
        pub fn initComptime(comptime options: Options) !Self {
            if (!@inComptime()) panic("Invalid at runtime.", .{});
            verifyContext(options.ctx);

            // initialize all slots as empty
            const kvs = blk: {
                var buf: [options.init_capacity]KV = undefined;
                break :blk &buf; // pointer to ro-data
            };
            for (kvs) |*kv| kv.* = .{}; // KV{} defaults

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
                    self.kvs[index].setProbeDistance(probe_dist);
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

        /// Check if hashmap contains the `key`.
        pub fn contains(self: *Self, key: K) bool {
            _ = self;
            _ = key;
        }

        /// Copy over the current content ... having twice the size.
        fn grow() void {}

        /// Verify properties of `ctx`.
        fn verifyContext(comptime ctx: type) void {
            const info = @typeInfo(ctx);
            if (info != .Struct) {
                @compileError("Expected struct for 'ctx' argument, found " ++ @typeName(ctx));
            }

            const functions = .{
                .{ "eql", .{ K, K }, bool },
                .{ "hash", .{K}, u64 },
            };

            inline for (functions) |func| {
                const name = func[0];
                const in_types = func[1];
                const out_type = func[2];

                if (!@hasDecl(ctx, name)) {
                    @compileError("Expected function by name " ++ name ++ "in 'ctx'.");
                }
                const fn_type = @field(ctx, name);
                maple.typ.assertFn(fn_type, in_types, out_type);
            }
        }
    };
}
