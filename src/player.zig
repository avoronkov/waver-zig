const std = @import("std");
const wav = @import("wav");

const pulse = @import("./pulse.zig");

const Self = @This();

const c = @import("c");

allocator: std.mem.Allocator,
io: std.Io,
clock: std.Io.Clock,
pa_simple: *c.pa_simple,
output_file: ?[]const u8 = null,
output: std.ArrayList(i16) = .empty,
channels: usize,

pub fn init(a: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, channels: u8) !Self {
    std.log.info("Channels: {}", .{channels});
    const pa = try pulse.paSimpleNew(channels);

    return .{
        .allocator = a,
        .io = io,
        .clock = clock,
        .pa_simple = pa,
        .channels = @intCast(channels),
    };
}

pub fn deinit(self: *Self) void {
    pulse.paSimpleDrain(self.pa_simple) catch |err| {
        std.log.err("paSimpleDrain failed: {t}", .{ err });
    };
    pulse.paSimpleFree(self.pa_simple);
    if (self.output_file) |of| {
        self.allocator.free(of);
    }
    self.output.deinit(self.allocator);
}

// wave: { value(t: f64, channel: usize) error{Eof}!f64 }
pub fn play(self: *Self, wave: anytype) !void {
    var eof = false;
    var buffer: [4800]u8 = undefined;
    var frame: i64 = 0;
    var err: c_int = 0;
    const play_start = self.clock.now(self.io).toMicroseconds();
    const channels = self.channels;
    // std.debug.print("channels={}\n", .{ channels });
    while (!eof) {
        var written: usize = 0;
        const frames_per_cycle: usize = 120;
        L: for (0..frames_per_cycle) |i| {
            const fi: f64 = @floatFromInt(frame);
            const t: f64 = fi / pulse.SAMPLE_RATE;
            for (0..channels) |chan| {
                const v = wave.value(t) catch {
                    eof = true;
                    break :L;
                };
                // std.debug.print("play t={}, chan={} value={}\n", .{t, chan, v});
                const sv: c_short = @intFromFloat(10000 * v);
                const sb = i * 2 * channels + (chan * 2);
                const fb = sb + 2;
                std.mem.writePackedInt(c_short, buffer[sb..fb], 0, sv, .little);
                written = i * 2 * channels;

                try self.output.append(self.allocator, sv);
            }
            frame += 1;
        }
        if (written == 0) {
            break;
        }

        try pulse.check("pa_simple_write", c.pa_simple_write(self.pa_simple, &buffer, written, &err), &err);

        const written_ms: i64 = @divTrunc(1000000 * frame, pulse.SAMPLE_RATE);
        const finish = self.clock.now(self.io).toMicroseconds();
        const passed_ms = finish - play_start;
        const ahead = written_ms - passed_ms;
        // std.debug.print("written samples={}, ms={}, passed_ms={}, ahead={}\n", .{frame, written_ms, passed_ms, ahead});
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
        std.log.info("Saving wav file: {s}\n", .{ output_file });
        var out = try std.Io.Dir.cwd().createFile(self.io, output_file, .{});
        defer out.close(self.io);

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_file_writer: std.Io.File.Writer = out.writer(self.io, &stdout_buffer);
        const writer = &stdout_file_writer.interface;

        const data_size = self.output.items.len * @sizeOf(i16);

        var encoder = try wav.encoder(i16, writer, stdout_file_writer, pulse.SAMPLE_RATE, self.channels, data_size);

        try encoder.write(i16, self.output.items);
        // For some reason finalize does not work correctly with file writer.
        // try encoder.finalize();
    }
}
