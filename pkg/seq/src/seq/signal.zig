const std = @import("std");

const Self = @This();

time: ?f64 = null,
instrument: []const u8,
freq: f64,
duration_bits: i64,
amplitude: f64,

pub fn deinit(self: Self, a: std.mem.Allocator) void {
    a.free(self.instrument);
}
