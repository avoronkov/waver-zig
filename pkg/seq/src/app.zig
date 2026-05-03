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
    const thread = try std.Thread.spawn(.{}, Beeper.run, .{ &self.beeper, &self.tape });
    return thread;
}

test "01-seq.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/01-seq.pelia" };
    const output =
        \\[0] 'in' freq=440, amp=0.75, bits=1
        \\[2] 'in' freq=330, amp=0.75, bits=1
        \\[4] 'in' freq=440, amp=0.75, bits=1
        \\[6] 'in' freq=330, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "02-vars.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/02-vars.pelia" };
    const output =
        \\[0] 'in' freq=440, amp=0.75, bits=1
        \\[4] 'in' freq=660, amp=0.75, bits=1
        \\[8] 'in' freq=440, amp=0.75, bits=1
        \\[12] 'in' freq=660, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "03-notes.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/03-notes.pelia" };
    const output =
        \\[0] 'ins' freq=220, amp=0.75, bits=1
        \\[2] 'ins' freq=233.081880759046, amp=0.75, bits=1
        \\[4] 'ins' freq=220, amp=0.75, bits=1
        \\[6] 'ins' freq=233.081880759046, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
test "04-waveform.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/04-waveform.pelia" };
    const output =
        \\[0] 'sine' freq=220, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
test "05-transpose-chord.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/05-transpose-chord.pelia" };
    const output =
        \\[0] 'in' freq=293.6647679173985, amp=0.75, bits=1
        \\[0] 'in' freq=369.99442271162945, amp=0.75, bits=1
        \\[0] 'in' freq=440, amp=0.75, bits=1
        \\[0] 'in' freq=220, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
test "06-funcs.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/06-funcs.pelia" };
    const output =
        \\[0] 'sine' freq=261.6255653005882, amp=0.75, bits=1
        \\[0] 'sine' freq=329.62755691286264, amp=0.75, bits=1
        \\[0] 'sine' freq=391.9954359817458, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
// .{
//     .input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/07-snare-sample.pelia" },
//     const output =
//         \\[0] 'in' freq=440, amp=0.75, bits=1
//         \\[4] 'in' freq=660, amp=0.75, bits=1
//         \\[8] 'in' freq=440, amp=0.75, bits=1
//         \\[12] 'in' freq=660, amp=0.75, bits=1
//         \\
//     ,
// },
test "08-filter-am.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "1", "../../examples/08-filter-am.pelia" };
    const output =
        \\[0] 'in' freq=349.2282314329977, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "09-bits-range.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/09-bits-range.pelia" };
    const output =
        \\[4] 'ins' freq=220, amp=0.75, bits=1
        \\[6] 'ins' freq=220, amp=0.75, bits=1
        \\[8] 'ins' freq=220, amp=0.75, bits=1
        \\[10] 'ins' freq=220, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
test "11-stop.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/11-stop.pelia" };
    const output =
        \\[0] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        \\[2] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        \\[4] 'sine' freq=369.99442271162945, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}
test "12-user-signalers.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/12-user-signalers.pelia" };
    const output =
        \\[4] 'sine' freq=246.94165062806425, amp=0.75, bits=1
        \\[6] 'sine' freq=246.94165062806425, amp=0.75, bits=1
        \\[8] 'sine' freq=246.94165062806425, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "13-embeded-sample.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/13-embeded-sample.pelia" };
    const output =
        \\[0] 'Kick' freq=0, amp=0.75, bits=1
        \\[2] 'Kick' freq=0, amp=0.75, bits=1
        \\[4] 'Kick' freq=0, amp=0.75, bits=1
        \\[6] 'Kick' freq=0, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "14-std-functions.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/14-std-functions.pelia" };
    const output =
        \\[0] 'sine' freq=220, amp=0.75, bits=1
        \\[2] 'sine' freq=261.6255653005882, amp=0.75, bits=1
        \\[4] 'sine' freq=329.62755691286264, amp=0.75, bits=1
        \\[6] 'sine' freq=220, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "15-every-list.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/15-every-list.pelia" };
    const output =
        \\[0] 'sine' freq=220, amp=0.75, bits=1
        \\[2] 'sine' freq=261.6255653005882, amp=0.75, bits=1
        \\[5] 'sine' freq=329.62755691286264, amp=0.75, bits=1
        \\[8] 'sine' freq=220, amp=0.75, bits=1
        \\[10] 'sine' freq=261.6255653005882, amp=0.75, bits=1
        \\[13] 'sine' freq=329.62755691286264, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "16-multiple-signal-funcations.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "3", "../../examples/16-multiple-signal-funcations.pelia" };
    const output =
        \\[0] 'inst' freq=195.9977179908729, amp=0.75, bits=1
        \\[0] 'inst' freq=246.94165062806425, amp=0.5, bits=1
        \\[0] 'inst' freq=293.6647679173985, amp=0.25, bits=3
        \\[0] 'inst' freq=391.9954359817458, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

fn testExample(input: []const [*:0]const u8, output: []const u8) !void {
    const io = std.testing.io;
    const clock = std.Io.Clock.real;
    const allocator = std.testing.allocator;

    const pargs: std.process.Args = .{ .vector = input };

    var buf: [4096]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buf);

    var app = try Self.init(allocator, io, clock, pargs, &stream);
    defer app.deinit();

    var t = try app.run();
    t.join();

    try std.testing.expectEqualStrings(output, buf[0..stream.end]);
}
