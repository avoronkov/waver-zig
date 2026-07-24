const std = @import("std");
const wav = @import("wav");

const Self = @This();

pub const PaPtr = ?*i32;

child: std.process.Child,
io: std.Io,

pub fn init(io: std.Io, sample_rate: usize, channels: usize) !Self {
    var child = try std.process.spawn(io, .{
        .argv = &.{"paplay", "--playback", "--latency-msec=100"},
        .stdin = .pipe,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    var paplay_buffer: [4800]u8 = undefined;
    var stdin_writer = child.stdin.?.writer(io, &paplay_buffer);
    var paplay_writer = &stdin_writer.interface;

    const data_size = 3600 * sample_rate * channels;
    const encoder = try wav.encoder(i16, paplay_writer, stdin_writer, sample_rate, channels, data_size);
    _ = encoder;
    try paplay_writer.flush();
    
    return .{
        .child = child,
        .io = io,
    };
}

pub fn write(self: *Self, data: []u8) !void {
    var paplay_buffer: [4800]u8 = undefined;
    var stdin_writer = self.child.stdin.?.writer(self.io, &paplay_buffer);
    var paplay_writer = &stdin_writer.interface;

    try paplay_writer.writeAll(data);
}

pub fn deinit(self: *Self) void {
    self.child.stdin.?.close(self.io);
    self.child.stdin = null;

    _ = self.child.wait(self.io) catch |err| {
        std.log.err("Child wait failed: {t}", .{err});
    };
}
