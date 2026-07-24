const std = @import("std");
const wav = @import("wav");

const Self = @This();

pub const PaPtr = ?*i32;

child: std.process.Child,
io: std.Io,
file_writer: ?std.Io.File.Writer,
buffer: [1024]u8,

pub fn init(io: std.Io, sample_rate: usize, channels: usize) !Self {
    var child = try std.process.spawn(io, .{
        .argv = &.{"paplay", "--playback", "--latency-msec=100"},
        .stdin = .pipe,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    var buffer: [1024]u8 = undefined;
    var file_writer = child.stdin.?.writer(io, &buffer);
    var paplay_writer = &file_writer.interface;

    const data_size = 3600 * sample_rate * channels;
    const encoder = try wav.encoder(i16, paplay_writer, file_writer, sample_rate, channels, data_size);
    _ = encoder;
    try paplay_writer.flush();
    
    return .{
        .child = child,
        .io = io,
        .file_writer = null,
        // SAFETY: used as a writer buffer.
        .buffer = undefined,
    };
}

pub fn write(self: *Self, data: []u8) !void {
    var writer = blk: { if (self.file_writer) |*writer| {
        break :blk writer;
    } else {
        self.file_writer = self.child.stdin.?.writer(self.io, &self.buffer);
        break :blk &self.file_writer.?;
    }};
    try writer.interface.writeAll(data);
}

pub fn deinit(self: *Self) void {
    self.child.stdin.?.close(self.io);
    self.child.stdin = null;

    _ = self.child.wait(self.io) catch |err| {
        std.log.err("Child wait failed: {t}", .{err});
    };
}
