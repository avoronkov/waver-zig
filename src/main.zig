const std = @import("std");
const player = @import("./player.zig");
const seq = @import("seq");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const clock = std.Io.Clock.real;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = try seq.init(allocator, io, clock, init.minimal.args, stdout);
    defer app.deinit();

    app.beeper.setTempo(60);

    var play = try player.init(allocator, io, clock);
    defer play.deinit();

    var t = try app.run();

    try play.play(&app.tape);

    t.join();

    std.log.info("OK", .{});
}
