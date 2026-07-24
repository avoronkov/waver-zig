const std = @import("std");
const wav = @import("wav");
const config = @import("config");

const with_paplay = config.WITH_PAPLAY;

pub const SAMPLE_RATE = 48000;

const Pulse = if (with_paplay) @import("./paplay.zig") else @import("./pulse.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
clock: std.Io.Clock,
pa: Pulse,
output_file: ?[]const u8 = null,
output: std.ArrayList(i16) = .empty,
channels: usize,

pub fn init(a: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, channels: u8) !Self {
    std.debug.print("config = {any}\n", .{config});
    std.log.info("Channels: {}", .{channels});
    std.log.info("paplay backend: {}", .{with_paplay});
    const pa = try Pulse.init(io, SAMPLE_RATE, channels);

    return .{
        .allocator = a,
        .io = io,
        .clock = clock,
        .pa = pa,
        .channels = @intCast(channels),
    };
}

pub fn deinit(self: *Self) void {
    self.pa.deinit();
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
    const play_start = self.clock.now(self.io).toMicroseconds();
    const channels = self.channels;

    while (!eof) {
        var written: usize = 0;
        const frames_per_cycle: usize = buffer.len / 2 / channels;
        L: for (0..frames_per_cycle) |i| {
            const fi: f64 = @floatFromInt(frame);
            const t: f64 = fi / SAMPLE_RATE;
            for (0..channels) |chan| {
                const v = wave.value(t, chan) catch {
                    eof = true;
                    break :L;
                };
                const sv: c_short = @intFromFloat(10000 * v);
                const sb = i * 2 * channels + (chan * 2);
                const fb = sb + 2;
                std.mem.writePackedInt(c_short, buffer[sb..fb], 0, sv, .little);

                try self.output.append(self.allocator, sv);
            }
            written = i * 2 * channels;
            frame += 1;
        }
        if (written == 0) {
            break;
        }

        try self.pa.write(buffer[0..written]);

        const written_ms: i64 = @divTrunc(1000000 * frame, SAMPLE_RATE);
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
        std.log.info("Saving wav file: {s}\n", .{output_file});
        var out = try std.Io.Dir.cwd().createFile(self.io, output_file, .{});
        defer out.close(self.io);

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_file_writer: std.Io.File.Writer = out.writer(self.io, &stdout_buffer);
        const writer = &stdout_file_writer.interface;

        const data_size = self.output.items.len * @sizeOf(i16);

        var encoder = try wav.encoder(i16, writer, stdout_file_writer, SAMPLE_RATE, self.channels, data_size);

        try encoder.write(i16, self.output.items);
        // For some reason finalize does not work correctly with file writer.
        // try encoder.finalize();
    }
}
