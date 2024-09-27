// Author: palsmo

const std = @import("std");

const net = std.net;
const posix = std.posix;

const MAX_UDP_PAYLOAD_SIZE_B = 65507;

pub const Server = struct {
    const Self = @This();

    socket_id: posix.socket_t,
    socket_addr: net.Address,

    pub fn init(address: []const u8, port: u16) !Self {
        const socket_addr = try net.Address.parseIp4(address, port);
        const socket_id = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, posix.IPPROTO.UDP);
        errdefer posix.close(socket_id);

        try posix.setsockopt(
            socket_id,
            posix.SOL.SOCKET,
            posix.SO.REUSEADDR,
            &[_]u8{1},
        );

        try posix.bind(socket_id, &(socket_addr.any), socket_addr.getOsSockLen());

        return .{
            .socket_id = socket_id,
            .socket_addr = socket_addr,
        };
    }

    /// Closes the file handler/descriptor.
    pub fn deinit(self: *Self) void {
        posix.close(self.socket_id);
    }

    /// Listener loop, can this be more efficient?
    pub fn loop(self: *const Self) void {
        std.log.info("Listening on {any} ...\n", .{self.socket_addr});

        var buf: [MAX_UDP_PAYLOAD_SIZE_B]u8 = undefined;
        var other_addr: posix.sockaddr = undefined;
        var other_addrlen: posix.socklen_t = @sizeOf(posix.sockaddr);

        while (true) {
            const n_recv = try posix.recvfrom(
                self.socket,
                &buf,
                0,
                &other_addr,
                &other_addrlen,
            );

            try self.processData(buf[0..n_recv]);

            std.log.info(
                "Received {d} byte(s) from {any};\nstring: {s}",
                .{ n_recv, other_addr, buf[0..n_recv] },
            );
        }
    }

    pub fn processData(self: *const Self, data: []const u8) !void {
        _ = self;
        _ = data;
        // this can proably be a user provided context.
    }
};

//pub fn server() !void {
//    const socket_addr = try net.Address.parseIp4("0.0.0.0", 44444);
//
//    const socket_id = try posix.socket(
//        posix.AF.INET,
//        posix.SOCK.DGRAM,
//        posix.IPPROTO.UDP,
//    );
//    defer posix.close(socket_id);
//
//    try posix.bind(socket_id, &socket_addr.any, socket_addr.getOsSockLen());
//
//    var buf: [MAX_UDP_PAYLOAD_SIZE_B]u8 = undefined;
//    var other_addr: posix.sockaddr = undefined;
//    var other_addrlen: posix.socklen_t = @sizeOf(posix.sockaddr);
//
//    std.log.info("Listen on {any} ...\n", .{socket_addr});
//
//    while (true) {
//        const n_recv = try posix.recvfrom(
//            socket_id,
//            &buf,
//            0, // * no flags
//            &other_addr,
//            &other_addrlen,
//        );
//        std.log.info(
//            "received {d} byte(s) from {any};\nstring: {s}",
//            .{ n_recv, other_addr, buf[0..n_recv] },
//        );
//    }
//}
//
//pub fn main() !void {
//    try server();
//}
