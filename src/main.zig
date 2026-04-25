const std = @import("std");
const pulse = @import("./pulse.zig");
const sequencer = @import("sequencer");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const clock = std.Io.Clock.real;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = try sequencer.App.init(allocator, io, clock, init.minimal.args, stdout);
    defer app.deinit();

    app.beeper.setTempo(60);

    const s = try pulse.paSimpleNew();
    defer pulse.paSimpleFree(s);

    var t = try app.run();

    try pulse.play(s, io, clock, &app.tape);

    t.join();

    try pulse.paSimpleDrain(s);

    std.log.info("OK", .{});
}
