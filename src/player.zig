const std = @import("std");
const wav = @import("wav");
const config = @import("config");

const with_paplay = config.WITH_PAPLAY;

const Pulse = if (with_paplay) @import("./paplay.zig") else @import("./pulse.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
clock: std.Io.Clock,
pa: Pulse,
output_file: ?[]const u8 = null,
output: std.ArrayList(i16) = .empty,
channels: usize,
sample_rate: i64,

pub fn init(
    a: std.mem.Allocator,
    io: std.Io,
    clock: std.Io.Clock,
    channels: u8,
    sample_rate: i64
) !Self {
    std.log.info("Channels: {}", .{channels});
    std.log.info("paplay backend: {}", .{with_paplay});
    std.log.info("Sample rate: {}", .{sample_rate});
    const pa = try Pulse.init(io, @intCast(sample_rate), channels);

    return .{
        .allocator = a,
        .io = io,
        .clock = clock,
        .pa = pa,
        .channels = @intCast(channels),
        .sample_rate = sample_rate,
    };
}

pub fn deinit(self: *Self) void {
    self.pa.deinit();
    if (self.output_file) |of| {
        self.allocator.free(of);
    }
    self.output.deinit(self.allocator);
}

const max_int16_amp = (1 << 14) - 1;

fn writeSamples(self: *Self, wave: anytype, frame: i64, frames_to_write: usize) !i64 {
    var buffer: [4800]u8 = undefined;
    var written: usize = 0;
    const sample_rate: f64 = @floatFromInt(self.sample_rate);
    const max_frames: usize = buffer.len / 2 / self.channels;
    const ftw: usize = @min(frames_to_write, max_frames);

    var f: i64 = frame;

    var eof: bool = false;
    L: for (0..ftw) |i| {
        const fi: f64 = @floatFromInt(f);
        const t: f64 = fi / sample_rate;
        for (0..self.channels) |chan| {
            var v = wave.value(t, chan) catch {
                eof = true;
                break :L;
            };

            if (v > 1.0) {
                // std.log.warn("Signal overflow: {}", .{v});
                v = 1.0;
            } else if (v < -1.0) {
                // std.log.warn("Signal underflow: {}", .{v});
                v = -1.0;
            }

            const sv: c_short = @intFromFloat(max_int16_amp * v);
            const sb = i * 2 * self.channels + (chan * 2);
            const fb = sb + 2;
            std.mem.writePackedInt(c_short, buffer[sb..fb], 0, sv, .little);

            if (self.output_file != null) {
                try self.output.append(self.allocator, sv);
            }
        }
        written = i * 2 * self.channels;
        f += 1;
    }
    if (written > 0) {
        try self.pa.write(buffer[0..written]);
    }
    if (eof) {
        return error.Eof;
    }
    return f;
}

// wave: { value(t: f64, channel: usize) error{Eof}!f64 }
pub fn play(self: *Self, wave: anytype) !void {
    var frame: i64 = 0;
    const play_start = self.clock.now(self.io).toMicroseconds();

    const min_samples: usize = 512;

    L: while (true) {
        const now = self.clock.now(self.io).toMicroseconds();
        const passed_ms = now - play_start;
        const to_write_frames = @divTrunc(passed_ms * self.sample_rate, 1000000);
        const frames_to_write: usize = @intCast(to_write_frames - frame);
        if (frames_to_write > min_samples) {
            frame = self.writeSamples(wave, frame, frames_to_write) catch |err| {
               if (err == error.Eof) {
                   break :L;
               }
               return err;
            };
        }
        else {
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
    }
    std.log.info("Frames written: {}\n", .{frame});

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

        var encoder = try wav.encoder(i16, writer, stdout_file_writer, @intCast(self.sample_rate), self.channels, data_size);

        try encoder.write(i16, self.output.items);
        // For some reason finalize does not work correctly with file writer.
        // try encoder.finalize();
    }
}
