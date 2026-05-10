const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
input: ?[]const u8 = null,
dump_wav: bool = false,
stop: ?i64 = null,
channels: u8 = 2,

pub fn init(a: std.mem.Allocator, pargs: std.process.Args) !Self {
    var res = Self{
        .allocator = a,
    };

    var args = pargs.iterate();
    _ = args.next();
    while (args.next()) |ar| {
        if (std.mem.eql(u8, ar, "--stop") or std.mem.eql(u8, ar, "-s")) {
            if (args.next()) |ar2| {
                res.stop = try std.fmt.parseInt(i64, ar2, 10);
            } else {
                return error.badArg;
            }
            continue;
        }
        if (std.mem.eql(u8, ar, "--dump-wav") or std.mem.eql(u8, ar, "-w")) {
            res.dump_wav = true;
            continue;
        }
        if (std.mem.eql(u8, ar, "--mono") or std.mem.eql(u8, ar, "-m")) {
            res.channels = 1;
            continue;
        }

        if (res.input) |input| {
            std.log.err("Input file is specified twice: {s}, {s}", .{input, ar});
        }

        res.input = try a.dupe(u8, ar);
    }
    return res;
}

pub fn deinit(self: Self) void {
    if (self.input) |input| {
        self.allocator.free(input);
    }
}
