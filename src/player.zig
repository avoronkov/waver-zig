const std = @import("std");
const pulse = @import("./pulse.zig");

const Self = @This();

const c = @import("c");

allocator: std.mem.Allocator,
io: std.Io,
clock: std.Io.Clock,
pa_simple: *c.pa_simple,
output_file: ?[]const u8 = null,
output: std.ArrayList(u8) = .empty,

pub fn init(a: std.mem.Allocator, io: std.Io, clock: std.Io.Clock) !Self {
    const pa = try pulse.paSimpleNew();

    return .{
        .allocator = a,
        .io = io,
        .clock = clock,
        .pa_simple = pa,
    };
}

pub fn deinit(self: *Self) void {
    pulse.paSimpleDrain(self.pa_simple) catch |err| {
        std.log.err("paSimpleDrain failed: {t}", .{ err });
    };
    pulse.paSimpleFree(self.pa_simple);
    self.output.deinit(self.allocator);
}

// wave: { value(t: f64, channel: usize) error{Eof}!f64 }
pub fn play(self: *Self, wave: anytype) !void {
    var eof = false;
    var buffer: [4800]u8 = undefined;
    var frame: i64 = 0;
    var err: c_int = 0;
    const play_start = self.clock.now(self.io).toMicroseconds();
    const channels = pulse.paSampleSpec.channels;
    while (!eof) {
        var written: usize = 0;
        for (0..480 / 4) |i| {
            const fi: f64 = @floatFromInt(frame);
            const t: f64 = fi / pulse.SAMPLE_RATE;
            for (0..channels) |chan| {
                std.debug.print("play t={}, chan={}\n", .{t, chan});
                const v = wave.value(t, chan) catch {
                    eof = true;
                    break;
                };
                const sv: c_short = @intFromFloat(10000 * v);
                const sb = i * 2 * channels + (chan * 2);
                const fb = sb + 2;
                std.mem.writePackedInt(c_short, buffer[sb..fb], 0, sv, .little);
                written = i * 2 + 2;
            }
            frame += 1;
        }
        if (written == 0) {
            break;
        }

        try pulse.check("pa_simple_write", c.pa_simple_write(self.pa_simple, &buffer, written, &err), &err);

        if (self.output_file) |_| {
            try self.output.appendSlice(self.allocator, buffer[0..written]);
        }

        const written_ms: i64 = @divTrunc(1000000 * frame, pulse.SAMPLE_RATE);
        const finish = self.clock.now(self.io).toMicroseconds();
        const passed_ms = finish - play_start;
        const ahead = written_ms - passed_ms;
        if (ahead > 5000) {
            const sleep_ns: u64 = @intCast((ahead - 5000) * 1000);
            try self.io.sleep(.fromNanoseconds(sleep_ns), .awake);
        }
    }
    std.log.info("Samples written: {}\n", .{frame});

    try self.saveWavFile();
}

fn saveWavFile(self: Self) !void {
    if (self.output_file) |output_file| {
        _ = output_file;
    }
}
