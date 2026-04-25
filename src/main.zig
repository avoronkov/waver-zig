const std = @import("std");
const pulse = @import("./pulse.zig");
const Args = @import("./args.zig");

const sequencer = @import("sequencer");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = try Args.init(allocator, init.minimal.args);
    defer args.deinit();

    if (args.input.len == 0) {
        std.log.err("No input file specified.\n", .{});
        return error.noInput;
    }

    const io = init.io;
    const clock = std.Io.Clock.real;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = try sequencer.App.init(allocator, io, clock, args.input, stdout, args.stop);
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
