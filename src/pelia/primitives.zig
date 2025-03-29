const std = @import("std");

pub fn Str(comptime n: usize) type {
    return struct {
        const Self = @This();

        value: [n]u8,
        length: usize,

        pub fn init(val: []const u8) !Self {
            if (val.len > n) {
                return error.tooBig;
            }
            var str = Self{
                .value = std.mem.zeroes([n]u8),
                .length = val.len,
            };
            std.mem.copyForwards(u8, &str.value, val);
            return str;
        }

        pub fn initComptime(comptime val: []const u8) Self {
            if (val.len > n) {
                @compileError("Str.initComptime: string is too big");
            }
            var str = Self{
                .value = std.mem.zeroes([n]u8),
                .length = val.len,
            };
            std.mem.copyForwards(u8, &str.value, val);
            return str;
        }

        pub fn string(self: *const Self) []const u8 {
            const res = self.value[0..self.length];
            return res;
        }
    };
}

pub const Ident = Str(64);

pub const Path = Str(128);
