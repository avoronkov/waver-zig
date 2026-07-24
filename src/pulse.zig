const std = @import("std");

const c = @import("c");

pub const SAMPLE_RATE = 48000;

pub const PaPtr = *c.pa_simple;

pub fn check(msg: []const u8, ret: i32, err: *c_int) !void {
    if (ret < 0) {
        std.log.err("failed {s}: {s}\n", .{ msg, c.pa_strerror(err.*) });
        return error.PA;
    }
}

pub fn paSimpleNew(channels: u8) !PaPtr {
    const spec: c.pa_sample_spec = .{
        .format = c.PA_SAMPLE_S16LE,
        .rate = SAMPLE_RATE,
        .channels = channels,
    };

    var err: c_int = 0;
    const s = c.pa_simple_new(null, "alxr-pulse", c.PA_STREAM_PLAYBACK, null, "playback", &spec, null, null, &err) orelse {
        std.log.err("pa_simple_new failed: {s}\n", .{c.pa_strerror(err)});
        return error.PA;
    };
    return s;
}

pub inline fn paSimpleWrite(s: PaPtr, buffer: [4800]u8, written: usize) !void {
    var err: c_int = 0;
    try check("pa_simple_write", c.pa_simple_write(s, &buffer, written, &err), &err);
}

pub fn paSimpleDrain(s: PaPtr) !void {
    var err: c_int = 0;
    try check("pa_simple_drain", c.pa_simple_drain(s, &err), &err);
}

pub fn paSimpleFree(s: PaPtr) void {
    c.pa_simple_free(s);
}
