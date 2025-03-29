const std = @import("std");

const c = @cImport({
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

pub const SAMPLE_RATE = 48000;

pub const paSampleSpec: c.pa_sample_spec = .{
    .format = c.PA_SAMPLE_S16LE,
    .rate = SAMPLE_RATE,
    .channels = 1,
};

pub fn check(msg: []const u8, ret: i32, err: *c_int) !void {
    if (ret < 0) {
        std.debug.print("failed {s}: {s}\n", .{ msg, c.pa_strerror(err.*) });
        return error.PA;
    }
}

pub fn paSimpleNew() !*c.pa_simple {
    var err: c_int = 0;
    const s = c.pa_simple_new(null, "alxr-pulse", c.PA_STREAM_PLAYBACK, null, "playback", &paSampleSpec, null, null, &err) orelse {
        std.debug.print("pa_simple_new failed: {s}\n", .{c.pa_strerror(err)});
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

// wave: { value(t: f64) error{Eof}!f64 }
pub fn play(pa: *c.pa_simple, wave: anytype) !void {
    var eof = false;
    var buffer: [4800]u8 = undefined;
    var frame: i64 = 0;
    var err: c_int = 0;
    const play_start = std.time.microTimestamp();
    while (!eof) {
        var written: usize = 0;
        for (0..480 / 2) |i| {
            const fi: f64 = @floatFromInt(frame);
            const t: f64 = fi / SAMPLE_RATE;
            const v = wave.value(t) catch {
                eof = true;
                break;
            };
            const sv: c_short = @intFromFloat(10000 * v);
            std.mem.writePackedInt(c_short, buffer[i * 2 .. i * 2 + 2], 0, sv, .little);
            written = i * 2 + 2;
            frame += 1;
        }
        if (written == 0) {
            break;
        }

        // const start = std.time.microTimestamp();
        try check("pa_simple_write", c.pa_simple_write(pa, &buffer, written, &err), &err);

        const written_ms: i64 = @divTrunc(1000000 * frame, SAMPLE_RATE);
        const finish = std.time.microTimestamp();
        // const dt = finish - start;
        const passed_ms = finish - play_start;
        const ahead = written_ms - passed_ms;
        // std.debug.print("Wrote buffer in {} micros (ahead: {} micros)\n", .{dt, ahead});
        if (ahead > 5000) {
            const sleep: u64 = @intCast((ahead - 5000) * 1000);
            // std.debug.print("sleep {}\n", .{sleep});
            std.time.sleep(sleep);
        }
    }
    std.debug.print("Samples written: {}\n", .{frame});
}
