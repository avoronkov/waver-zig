const std = @import("std");
const Tape = @import("./tape.zig");
const Beeper = @import("./beeper.zig");
const rand = @import("./seq/rand.zig");
const Args = @import("./args.zig");

pub const App = struct{
    allocator: std.mem.Allocator,
    io: std.Io,
    clock: std.Io.Clock,
    tape: Tape,
    beeper: Beeper,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, input_file: []const u8, log: *std.Io.Writer, stop: ?i64) !App {
        rand.init(io, clock);

        const tape = Tape.init(allocator);

        var beeper = try Beeper.init(allocator, io, clock, input_file, 250 * 1000, stop);
        beeper.log = log;

        return .{
            .allocator = allocator,
            .io = io,
            .clock = clock,
            .tape = tape,
            .beeper = beeper,
        };
    }

    pub fn deinit(self: *App) void {
        self.beeper.deinit();
        self.tape.deinit();
    }

    pub fn run(self: *App) !std.Thread {
        const thread = try std.Thread.spawn(.{}, Beeper.run, .{&self.beeper, &self.tape});
        return thread;
    }
};

test "01-seq.pelia" {
    const io = std.testing.io;
    const clock = std.Io.Clock.real;
    const allocator = std.testing.allocator;
    const file = "../../examples/01-seq.pelia";
    var buf: [4096]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buf);

    var app = try App.init(allocator, io, clock, file, &stream, 8);
    defer app.deinit();

    var t = try app.run();
    t.join();

    const exp = 
        \\[0] 'in' freq=440, amp=0.75, dur=0.25
        \\[2] 'in' freq=330, amp=0.75, dur=0.25
        \\[4] 'in' freq=440, amp=0.75, dur=0.25
        \\[6] 'in' freq=330, amp=0.75, dur=0.25
        \\
    ;

    try std.testing.expectEqualStrings(buf[0..stream.end], exp);
}
