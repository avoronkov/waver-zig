const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
input: []const u8,
stop: ?i64,

pub fn init(a: std.mem.Allocator, pargs: std.process.Args) !Self {
    var ss = try a.alloc(u8, 0);
    errdefer a.free(ss);

    var stop: ?i64 = null;

    var args = pargs.iterate();
    _ = args.next();
    while (args.next()) |ar| {
        if (std.mem.eql(u8, ar, "--stop")) {
            if (args.next()) |ar2| {
                stop = try std.fmt.parseInt(i64, ar2, 10);
            } else {
                return error.badArg;
            }
            continue;
        }
        a.free(ss);
        ss = try a.dupe(u8, ar);
        break;
    }
    return Self{
        .allocator = a,
        .input = ss,
        .stop = stop,
    };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.input);
}
