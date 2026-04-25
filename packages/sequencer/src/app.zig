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
    args: Args,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, pargs: std.process.Args, log: *std.Io.Writer) !App {
        const args = try Args.init(allocator, pargs);
        errdefer args.deinit();

        if (args.input.len == 0) {
            std.log.err("No input file specified.\n", .{});
            return error.noInput;
        }

        rand.init(io, clock);

        const tape = Tape.init(allocator);
        errdefer tape.deinit();

        var beeper = try Beeper.init(allocator, io, clock, args.input, args.stop);
        errdefer beeper.deinit();

        beeper.log = log;

        return .{
            .allocator = allocator,
            .io = io,
            .clock = clock,
            .args = args,
            .tape = tape,
            .beeper = beeper,
        };
    }

    pub fn deinit(self: *App) void {
        self.beeper.deinit();
        self.tape.deinit();
        self.args.deinit();
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

    const vector = [_][*:0]const u8{ "self", "--stop", "8", "../../examples/01-seq.pelia" };
    const pargs: std.process.Args = .{ .vector = &vector };

    var buf: [4096]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buf);

    var app = try App.init(allocator, io, clock, pargs, &stream);
    defer app.deinit();

    var t = try app.run();
    t.join();

    const exp = 
        \\[0] 'in' freq=440, amp=0.75, bits=1
        \\[2] 'in' freq=330, amp=0.75, bits=1
        \\[4] 'in' freq=440, amp=0.75, bits=1
        \\[6] 'in' freq=330, amp=0.75, bits=1
        \\
    ;

    try std.testing.expectEqualStrings(buf[0..stream.end], exp);
}
