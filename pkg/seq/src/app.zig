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

pub fn init(allocator: std.mem.Allocator, io: std.Io, clock: std.Io.Clock, pargs: std.process.Args, log: ?*std.Io.Writer) !Self {
    const args = try Args.init(allocator, pargs);
    errdefer args.deinit();

    if (args.help) {
        return error.helpRequested;
    }

    const input = if (args.input) |input| input else {
        std.log.err("No input file specified.\n", .{});
        return error.noInput;
    };

    const default_go_seed = 1;
    const the_seed: i64 = if (args.seed) |sd| sd else if (args.random_seed) blk: {
        var def_rand = std.Random.DefaultPrng.init(@intCast(std.Io.Timestamp.now(io, .awake).toMilliseconds()));
        const seed = def_rand.random().int(i64);
        break :blk seed;
    } else default_go_seed;
    std.log.info("Seed: {}", .{the_seed});
    rand.init(the_seed);

    var tape = Tape.init(allocator, io);
    errdefer tape.deinit();

    var beeper = try Beeper.init(allocator, io, clock, input, args.stop);
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
        \\[0] 'in' "440" freq=440, amp=0.75, bits=2
        \\[2] 'in' "330" freq=330, amp=0.75, bits=2
        \\[4] 'in' "440" freq=440, amp=0.75, bits=2
        \\[6] 'in' "330" freq=330, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "02-vars.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/02-vars.pelia" };
    const output =
        \\[0] 'in' "440" freq=440, amp=0.75, bits=4
        \\[4] 'in' "660" freq=660, amp=0.75, bits=4
        \\[8] 'in' "440" freq=440, amp=0.75, bits=4
        \\[12] 'in' "660" freq=660, amp=0.75, bits=4
        \\
    ;
    try testExample(input, output);
}

test "03-notes.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/03-notes.pelia" };
    const output =
        \\[0] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\[2] 'ins' "Bb3" freq=233.081880759046, amp=0.75, bits=2
        \\[4] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\[6] 'ins' "Bb3" freq=233.081880759046, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}
test "04-waveform.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/04-waveform.pelia" };
    const output =
        \\[0] 'sine' "A3" freq=220, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}
test "05-transpose-chord.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/05-transpose-chord.pelia" };
    const output =
        \\[0] 'in' "D4" freq=293.6647679173985, amp=0.75, bits=2
        \\[0] 'in' "Gb4" freq=369.99442271162945, amp=0.75, bits=2
        \\[0] 'in' "A4" freq=440, amp=0.75, bits=2
        \\[0] 'in' "A3" freq=220, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}
test "06-funcs.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "2", "../../examples/06-funcs.pelia" };
    const output =
        \\[0] 'sine' "C4" freq=261.6255653005882, amp=0.75, bits=2
        \\[0] 'sine' "E4" freq=329.62755691286264, amp=0.75, bits=2
        \\[0] 'sine' "G4" freq=391.9954359817458, amp=0.75, bits=2
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
        \\[0] 'in' "F4" freq=349.2282314329977, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "09-bits-range.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/09-bits-range.pelia" };
    const output =
        \\[4] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\[6] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\[8] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\[10] 'ins' "A3" freq=220, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}
test "11-stop.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/11-stop.pelia" };
    const output =
        \\[0] 'sine' "Gb4" freq=369.99442271162945, amp=0.75, bits=2
        \\[2] 'sine' "Gb4" freq=369.99442271162945, amp=0.75, bits=2
        \\[4] 'sine' "Gb4" freq=369.99442271162945, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}
test "12-user-signalers.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/12-user-signalers.pelia" };
    const output =
        \\[4] 'sine' "B3" freq=246.94165062806425, amp=0.75, bits=2
        \\[6] 'sine' "B3" freq=246.94165062806425, amp=0.75, bits=2
        \\[8] 'sine' "B3" freq=246.94165062806425, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "13-embeded-sample.pelia" {
    const input = &[_][*:0]const u8{ "self", "../../examples/13-embeded-sample.pelia" };
    const output =
        \\[0] 'Kick' "0" freq=0, amp=0.75, bits=2
        \\[2] 'Kick' "0" freq=0, amp=0.75, bits=2
        \\[4] 'Kick' "0" freq=0, amp=0.75, bits=2
        \\[6] 'Kick' "0" freq=0, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "14-std-functions.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/14-std-functions.pelia" };
    const output =
        \\[0] 'sine' "A3" freq=220, amp=0.75, bits=2
        \\[2] 'sine' "C4" freq=261.6255653005882, amp=0.75, bits=2
        \\[4] 'sine' "E4" freq=329.62755691286264, amp=0.75, bits=2
        \\[6] 'sine' "A3" freq=220, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "15-every-list.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/15-every-list.pelia" };
    const output =
        \\[0] 'sine' "A3" freq=220, amp=0.75, bits=2
        \\[2] 'sine' "C4" freq=261.6255653005882, amp=0.75, bits=3
        \\[5] 'sine' "E4" freq=329.62755691286264, amp=0.75, bits=3
        \\[8] 'sine' "A3" freq=220, amp=0.75, bits=2
        \\[10] 'sine' "C4" freq=261.6255653005882, amp=0.75, bits=3
        \\[13] 'sine' "E4" freq=329.62755691286264, amp=0.75, bits=3
        \\
    ;
    try testExample(input, output);
}

test "16-multiple-signal-funcations.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "3", "../../examples/16-multiple-signal-funcations.pelia" };
    const output =
        \\[0] 'inst' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[0] 'inst' "B3" freq=246.94165062806425, amp=0.5, bits=3
        \\[0] 'inst' "D4" freq=293.6647679173985, amp=0.25, bits=2
        \\[0] 'inst' "G4" freq=391.9954359817458, amp=0.75, bits=3
        \\
    ;
    try testExample(input, output);
}

test "17-euclidian.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/17-euclidian.pelia" };
    const output =
        \\[0] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[3] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[6] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=2
        \\[8] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[11] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[14] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "18-euclidian-last.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "16", "../../examples/18-euclidian-last.pelia" };
    const output =
        \\[2] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[5] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=2
        \\[7] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[10] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\[13] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=2
        \\[15] 'sine' "G3" freq=195.9977179908729, amp=0.75, bits=3
        \\
    ;
    try testExample(input, output);
}

test "19-pan.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/19-pan.pelia" };
    const output =
        \\[0] 'l' "G3" freq=195.9977179908729, amp=0.75, bits=1
        \\[2] 'r' "G3" freq=195.9977179908729, amp=0.75, bits=1
        \\[4] 'l' "G3" freq=195.9977179908729, amp=0.75, bits=1
        \\[6] 'r' "G3" freq=195.9977179908729, amp=0.75, bits=1
        \\
    ;
    try testExample(input, output);
}

test "20-lisp.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/20-lisp.pelia" };
    const output =
        \\[0] 'in' "440" freq=440, amp=0.75, bits=1
        \\[1] 'in2' "660" freq=660, amp=0.75, bits=2
        \\[4] 'in' "440" freq=440, amp=0.75, bits=1
        \\[5] 'in2' "660" freq=660, amp=0.75, bits=2
        \\
    ;
    try testExample(input, output);
}

test "21-adsr.pelia" {
    const input = &[_][*:0]const u8{ "self", "--stop", "8", "../../examples/21-adsr.pelia" };
    const output =
        \\[0] 'in' "E3" freq=164.81377845643132, amp=0.75, bits=4
        \\[4] 'in' "E3" freq=164.81377845643132, amp=0.75, bits=4
        \\
    ;
    try testExample(input, output);
}

test "february/01-samples.pelia" {
    if (true) {
        // TODO need to examine this test: it takes too long to finish.
        return error.SkipZigTest;
    }
    const io = std.testing.io;
    const clock = std.Io.Clock.real;
    const allocator = std.testing.allocator;

    const input = &[_][*:0]const u8{ "self", "../../examples/february/01-samples.pelia" };
    const pargs: std.process.Args = .{ .vector = input };

    var app = try Self.init(allocator, io, clock, pargs, null);
    defer app.deinit();

    var t = try app.run();
    t.join();
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
