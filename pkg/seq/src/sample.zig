const std = @import("std");
const wav = @import("wav");
const Note = @import("./note.zig");
const EofError = @import("./wave.zig").EofError;

const samples = @import("samples").resources;

const Allocator = std.mem.Allocator;

pub const Sample = struct {
    allocator: Allocator,
    sample_rate: f64,
    data: []f32,
    channels: usize,

    pub fn value(self: *const Sample, t: f64, note: Note) EofError!f64 {
        const n: usize = @intFromFloat(t * self.sample_rate);
        const idx: usize = @intCast(self.channels * n + @rem(note.channel, self.channels));
        if (idx >= self.data.len) {
            return error.Eof;
        }
        return self.data[idx];
    }

    pub fn deinit(self: Sample) void {
        self.allocator.free(self.data);
    }

    pub fn copy(self: *const Sample) !Sample {
        return .{
            .allocator = self.allocator,
            .sample_rate = self.sample_rate,
            .data = try self.allocator.dupe(f32, self.data),
            .channels = self.channels,
        };
    }
};

pub fn parseSampleFile(a: Allocator, io: std.Io, filename: []const u8) !Sample {
    return parseFsFile(a, io, filename) catch |err| {
        if (err == error.FileNotFound) {
            return parseEmbededFile(a, filename);
        }
        return err;
    };
}

fn parseFsFile(a: Allocator, io: std.Io, filename: []const u8) !Sample {
    var file = try std.Io.Dir.cwd().openFile(io, filename, .{});
    defer file.close(io);

    var file_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &file_buffer);
    return parseWavReader(a, &file_reader.interface);
}

fn parseEmbededFile(a: Allocator, filename: []const u8) !Sample {
    if (samples.get(filename)) |content| {
        var reader = std.Io.Reader.fixed(content);
        return parseWavReader(a, &reader);
    }
    return error.FileNotFound;
}

fn parseWavReader(a: Allocator, reader: *std.Io.Reader) !Sample {
    var decoder = try wav.decoder(reader);

    var data: std.ArrayListUnmanaged(f32) = .empty;
    errdefer data.deinit(a);

    var buff: [64]f32 = undefined;
    while (true) {
        const samples_read = try decoder.read(f32, &buff);
        try data.appendSlice(a, buff[0..samples_read]);
        if (samples_read < buff.len) {
            break;
        }
    }

    const sample_rate: f64 = @floatFromInt(decoder.fmt.sample_rate);

    return .{
        .allocator = a,
        .sample_rate = sample_rate,
        .data = try data.toOwnedSlice(a),
        .channels = decoder.fmt.channels,
    };
}
