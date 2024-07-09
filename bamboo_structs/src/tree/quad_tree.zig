const std = @import("std");

const Allocator = std.mem.Allocator;

/// Manages two-dimensional spatial data,
pub const QuadTree = struct {
    const Self = @This();

    // child quadrant nodes
    nodes: ?struct {
        nw: *Self,
        ne: *Self,
        sw: *Self,
        se: *Self,
    } = null,

    // quadrant bounds
    bounds: struct {
        min_x: usize,
        min_y: usize,
        max_x: usize,
        max_y: usize,
    },

    // quadrant center
    center: ?struct { x: usize, y: usize } = null,

    // data
    point: ?struct { x: usize, y: usize } = null,

    // other
    allocator: Allocator,

    pub fn init(min_x: usize, min_y: usize, max_x: usize, max_y: usize, allocator: Allocator) !Self {
        return .{
            .bounds = .{
                .min_x = min_x,
                .min_y = min_y,
                .max_x = max_x,
                .max_y = max_y,
            },
            .allocator = allocator,
        };
    }

    /// Inserts `point` into the tree structure.
    pub fn insert(self: *Self, point: struct { x: usize, y: usize }) !void {

        // if `self` is empty and has no children, insert here
        if (self.point == null and self.nodes == null) {
            self.point = point;
            return;
        }

        // * here means 2 >= points fall into bounds of `self`,
        // this means bounds has room for more and can be divided

        // move `point` and existing point into children
        const point_ex = self.point.?;
        self.point = null;
        try insert_child(self, point_ex);
        try insert_child(self, point);
    }

    /// Inserts `point` in a child quadrant, subdivides `self` when necessary.
    fn insert_child(self: *Self, point: struct { x: usize, y: usize }) !void {

        // if first time exploring `self` => center not yet calculated
        if (self.center == null) {
            const center_x = (self.bounds.min_x + self.bounds.max_x) / 2;
            const center_y = (self.bounds.min_y + self.bounds.max_y) / 2;
            self.center = .{ .x = center_x, .y = center_y };
        }

        const center = self.center.?;
        const bounds = self.bounds;

        // determine the correct quadrant for `point` -->

        if (point.x < center.x) {
            if (point.y < center.y) {
                if (self.nodes.nw == null) {
                    const nw = try self.allocator.create(Self);
                    errdefer self.allocator.destroy(nw);
                    nw.* = Self.init(bounds.min_x, bounds.min_y, center.x, center.y, self.allocator);
                    self.nodes.nw = nw;
                }
                self.nodes.nw.?.insert(point);
            } else {
                if (self.nodes.sw == null) {
                    const sw = try self.allocator.create(Self);
                    errdefer self.allocator.destroy(sw);
                    sw.* = Self.init(bounds.min_x, center.y, center.x, bounds.max_y, self.allocator);
                    self.nodes.sw = sw;
                }
                self.nodes.sw.?.insert(point);
            }
        } else {
            if (point.y < center.y) {
                if (self.nodes.ne == null) {
                    const ne = try self.allocator.create(Self);
                    errdefer self.allocator.destroy(ne);
                    ne.* = Self.init(center.x, bounds.min_y, bounds.max_x, center.y, self.allocator);
                    self.nodes.ne = ne;
                }
                self.nodes.ne.?.insert(point);
            } else {
                if (self.nodes.se == null) {
                    const se = try self.allocator.create(Self);
                    errdefer self.allocator.destroy(se);
                    se.* = Self.init(center.x, center.y, bounds.max_x, bounds.max_y, self.allocator);
                    self.nodes.se = se;
                }
                self.nodes.se.?.insert(point);
            }
        }
    }

    // Searches for `point` in the quadtree.
    //pub fn search(self: *Self, point: struct { x: usize, y: usize }) void {
    //    const center_x = (self.min_x + self.max_x) / 2;
    //    const center_y = (self.min_y + self.max_y) / 2;

    //    if (point.x < center_x) {
    //        if (point.y < center_y and self.nw != null) {
    //            return self.nw.?.search(point);
    //        } else if (self.sw != null) {
    //            return self.sw.?.search(point);
    //        }
    //    } else {
    //        if (point.y < center_y and self.ne != null) {
    //            return self.ne.?.search(point);
    //        } else if (self.se != null) {
    //            return self.se.?.search(point);
    //        }
    //    }

    //    return null;
    //}
};
