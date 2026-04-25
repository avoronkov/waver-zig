const std = @import("std");
const App = @import("./app.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const clock = std.Io.Clock.real;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = try App.App.init(allocator, io, clock, init.minimal.args, stdout);
    defer app.deinit();

    app.beeper.setTempo(60);

    var t = try app.run();
    t.join();

    std.log.info("OK", .{});
}
