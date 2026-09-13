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

    var app = seq.init(allocator, io, clock, init.minimal.args, null) catch |err| {
        if (err == error.helpRequested) {
            try stdout.print(
                \\waver-zig
                \\usage:
                \\ --stop, -s <int> - stop after specified frame
                \\ --dump-wav, -w   - dump output into wav file
                \\ --mono, -m       - output audio in mono (legacy)
                \\ --verbose, -V    - verbose output
                \\ --help, -h       - show this help
                \\
                , .{});
            try stdout.flush(); // Don't forget to flush!
            return;
        }
        return err;
    };
    defer app.deinit();

    app.beeper.setTempo(120, 0);

    var play = try player.init(allocator, io, clock, app.args.channels);
    defer play.deinit();

    if (app.args.dump_wav) {
        if (app.args.input) |input| {
            play.output_file = try std.fmt.allocPrint(allocator, "{s}.wav", .{input});
        } else {
            std.debug.panic("Input file is not specified.", .{});
        }
    }

    if (app.args.verbose) {
        app.beeper.log = stdout;
    }

    var t = try app.run();

    try play.play(&app.tape);

    t.join();

    std.log.info("OK", .{});
}
