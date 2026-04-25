const std = @import("std");
const Tape = @import("./tape.zig");
const Beeper = @import("./beeper.zig");
const rand = @import("./seq/rand.zig");
const Args = @import("./args.zig");

const Self = @This();

allocator: std.mem.Allocator,
io: std.Io,
clock: std.Io.Clock,
tape: Tape,
beeper: Beeper,
args: Args,

pub fn init(allocator: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, pargs: std.process.Args, log: *std.Io.Writer) !Self {
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

pub fn deinit(self: *Self) void {
    self.beeper.deinit();
    self.tape.deinit();
    self.args.deinit();
}

pub fn run(self: *Self) !std.Thread {
    const thread = try std.Thread.spawn(.{}, Beeper.run, .{&self.beeper, &self.tape});
    return thread;
}

test "01-seq.pelia" {
    const Test = struct{
        input: []const [*:0]const u8,
        output: []const u8,
    };

    const io = std.testing.io;
    const clock = std.Io.Clock.real;
    const allocator = std.testing.allocator;

    const tests = [_]Test{
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/01-seq.pelia" },
            .output =
                \\[0] 'in' freq=440, amp=0.75, bits=1
                \\[2] 'in' freq=330, amp=0.75, bits=1
                \\[4] 'in' freq=440, amp=0.75, bits=1
                \\[6] 'in' freq=330, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/02-vars.pelia" },
            .output =
                \\[0] 'in' freq=440, amp=0.75, bits=1
                \\[4] 'in' freq=660, amp=0.75, bits=1
                \\[8] 'in' freq=440, amp=0.75, bits=1
                \\[12] 'in' freq=660, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/03-notes.pelia" },
            .output =
                \\[0] 'ins' freq=220, amp=0.75, bits=1
                \\[2] 'ins' freq=233.081880759046, amp=0.75, bits=1
                \\[4] 'ins' freq=220, amp=0.75, bits=1
                \\[6] 'ins' freq=233.081880759046, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/04-waveform.pelia" },
            .output =
                \\[0] 'sine' freq=220, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/05-transpose-chord.pelia" },
            .output =
                \\[0] 'in' freq=293.6647679173985, amp=0.75, bits=1
                \\[0] 'in' freq=369.99442271162945, amp=0.75, bits=1
                \\[0] 'in' freq=440, amp=0.75, bits=1
                \\[0] 'in' freq=220, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/06-funcs.pelia" },
            .output =
                \\[0] 'sine' freq=261.6255653005882, amp=0.75, bits=1
                \\[0] 'sine' freq=329.62755691286264, amp=0.75, bits=1
                \\[0] 'sine' freq=391.9954359817458, amp=0.75, bits=1
                \\
            ,
        },
        // .{
        //     .input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/07-snare-sample.pelia" },
        //     .output =
        //         \\[0] 'in' freq=440, amp=0.75, bits=1
        //         \\[4] 'in' freq=660, amp=0.75, bits=1
        //         \\[8] 'in' freq=440, amp=0.75, bits=1
        //         \\[12] 'in' freq=660, amp=0.75, bits=1
        //         \\
        //     ,
        // },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "1", "../../examples/08-filter-am.pelia" },
            .output =
                \\[0] 'in' freq=349.2282314329977, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/09-bits-range.pelia" },
            .output =
                \\[4] 'ins' freq=220, amp=0.75, bits=1
                \\[6] 'ins' freq=220, amp=0.75, bits=1
                \\[8] 'ins' freq=220, amp=0.75, bits=1
                \\[10] 'ins' freq=220, amp=0.75, bits=1
                \\
            ,
        },
        .{
            .input = &[_][*:0]const u8{ "self", "../../examples/11-stop.pelia" },
            .output =
                \\[0] 'sine' freq=369.99442271162945, amp=0.75, bits=1
                \\[2] 'sine' freq=369.99442271162945, amp=0.75, bits=1
                \\[4] 'sine' freq=369.99442271162945, amp=0.75, bits=1
                \\
            ,
        },

        // .{
        //     .input = &[_][*:0]const u8{ "self", "../../examples/12-user-signalers.pelia" },
        //     .output =
        //         \\[0] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        //         \\[2] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        //         \\[4] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        //         \\
        //     ,
        // },

    };

    for (tests) |ts| {
        const pargs: std.process.Args = .{ .vector = ts.input };

        var buf: [4096]u8 = undefined;
        var stream = std.Io.Writer.fixed(&buf);

        var app = try Self.init(allocator, io, clock, pargs, &stream);
        defer app.deinit();

        std.debug.print(">>> Testing {s}\n", .{ app.args.input });
        var t = try app.run();
        t.join();

        try std.testing.expectEqualStrings(ts.output, buf[0..stream.end]);
    }
}
