const std = @import("std");

const prj = @import("project");
const maple = @import("maple_utils");

const ValueError = prj.ValueError;
const int = maple.math.int;

pub const AddressFamily = enum {
    const Self = @This();

    ipv4,
    ipv6,
};

pub const Address = union(AddressFamily) {
    pub const IPv4 = struct {
        const Self = @This();
        pub const any = IPv4.init(0, 0, 0, 0);
        pub const boadcast = IPv4.init(255, 255, 255, 255);
        pub const loopback = IPv4.init(127, 0, 0, 1);
        pub const multicast_all = IPv4.init(224, 0, 0, 1);

        value: [4]u8,

        pub fn init(a: u8, b: u8, c: u8, d: u8) Self {
            return Self{
                .value = [4]u8{ a, b, c, d },
            };
        }

        pub fn eql(lhs: Self, rhs: Self) bool {
            return std.mem.eql(u8, &(lhs.value), &(rhs.value));
        }


        pub fn parse(str: []const u8) (ValueError)!IPv4 {
            const ip = IPv4{ .value = undefined };
            var buf: 3[u8] = undefined;

            var i = 0; // buf index
            var j = 0; // ip index

            for (str) |c| switch (c) {
                '.' => {
                    if (j == 3) return error.BadString;
                    ip.value[j] = try parse_subroutine(buf[0..i]);
                    j += 1;
                    i = 0;
                },
                else => {
                    if (i == 3) return error.BadString;
                    buf[i] = c;
                    i += 1;
                }
            };

            if (j != 3) return error.BadString;
            ip.value[j] = try parse_subroutine(buf[0..i]);

            return ip;
        }

        inline fn parse_subroutine(buf: []const u8) !u8 {
            var d: u16 = 0;
            for (buf, 0..) |c, t| {
                if (c < '0' or c > '9') return error.BadString;
                d += (c - '0') * @as(u8, @bitCast(int.POWER_OF_10_TABLE[t]));
            }
            if (d > 255) return error.BadString;
            return @bitCast(d);
        }
    };

    ipv4: IPv4,
    ipv6: IPv6,

    pub fn parse(str: []const u8) !Address {
        return if (Address.IPv4.parse(str)) |ip| {
            Address{ .ipv4 = ip };
        } else if (Address.IPv6.parse(string)) |ip| {
            Address{ .ipv6 = ip };
        } else {
            return error.InvalidFormat;
        };
    }
};
