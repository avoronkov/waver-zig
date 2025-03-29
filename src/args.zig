const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
input: []const u8,

pub fn init(a: std.mem.Allocator) !Self {
    var ss = try a.alloc(u8, 0);
    errdefer a.free(ss);

    var args = try std.process.argsWithAllocator(a);
    defer args.deinit();

    _ = args.next();
    while (args.next()) |ar| {
        a.free(ss);
        ss = try a.dupe(u8, ar);
        break;
    }
    return Self{
        .allocator = a,
        .input = ss,
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.input);
}
