const std = @import("std");

const Self = @This();

const c = @import("c");

pub const PaPtr = *c.pa_simple;

pa: PaPtr,

pub fn init(io: std.Io, sample_rate: usize, channels: u8) !Self {
    _ = io;
    return .{
        .pa = try paSimpleNew(sample_rate, channels),
    };
}

pub fn write(self: *Self, data: []u8) !void {
    try paSimpleWrite(self.pa, data);
}

pub fn deinit(self: *Self) void {
    paSimpleDrain(self.pa) catch |err| {
        std.log.err("paSimpleDrain failed: {t}", .{err});
    };
    paSimpleFree(self.pa);
}

fn check(msg: []const u8, ret: i32, err: *c_int) !void {
    if (ret < 0) {
        std.log.err("failed {s}: {s}\n", .{ msg, c.pa_strerror(err.*) });
        return error.PA;
    }
}

fn paSimpleNew(sample_rate: usize, channels: u8) !PaPtr {
    const spec: c.pa_sample_spec = .{
        .format = c.PA_SAMPLE_S16LE,
        .rate = @intCast(sample_rate),
        .channels = channels,
    };

    var err: c_int = 0;
    const s = c.pa_simple_new(null, "alxr-pulse", c.PA_STREAM_PLAYBACK, null, "playback", &spec, null, null, &err) orelse {
        std.log.err("pa_simple_new failed: {s}\n", .{c.pa_strerror(err)});
        return error.PA;
    };
    return s;
}

inline fn paSimpleWrite(s: PaPtr, buffer: []u8) !void {
    var err: c_int = 0;
    try check("pa_simple_write", c.pa_simple_write(s, buffer.ptr, buffer.len, &err), &err);
}

fn paSimpleDrain(s: PaPtr) !void {
    var err: c_int = 0;
    try check("pa_simple_drain", c.pa_simple_drain(s, &err), &err);
}

fn paSimpleFree(s: PaPtr) void {
    c.pa_simple_free(s);
}
