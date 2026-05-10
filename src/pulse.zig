const std = @import("std");

const c = @import("c");

pub const SAMPLE_RATE = 48000;

pub fn check(msg: []const u8, ret: i32, err: *c_int) !void {
    if (ret < 0) {
        std.log.err("failed {s}: {s}\n", .{ msg, c.pa_strerror(err.*) });
        return error.PA;
    }
}

pub fn paSimpleNew(channels: u8) !*c.pa_simple {
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

pub fn paSimpleDrain(s: *c.pa_simple) !void {
    var err: c_int = 0;
    try check("pa_simple_drain", c.pa_simple_drain(s, &err), &err);
}

pub fn paSimpleFree(s: *c.pa_simple) void {
    c.pa_simple_free(s);
}
