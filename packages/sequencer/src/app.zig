const std = @import("std");
const Tape = @import("./tape.zig");
const Beeper = @import("./beeper.zig");
const rand = @import("./seq/rand.zig");
const Args = @import("./args.zig");

pub fn process_file(allocator: std.mem.Allocator, input_file: []const u8, log: *std.Io.Writer, stop: ?i64) !void {
    rand.init();

    var tape = Tape.init(allocator);
    defer tape.deinit();

    var beeper = try Beeper.init(allocator, input_file, &tape, 250 * 1000, stop);
    defer beeper.deinit();

    beeper.log = log;

    var thread = try std.Thread.spawn(.{}, Beeper.run, .{&beeper});
    defer thread.join();
}

test "01-seq.pelia" {
    const allocator = std.testing.allocator;
    const file = "../../examples/01-seq.pelia";
    var buf: [4096]u8 = undefined;
    var stream = std.Io.Writer.fixed(&buf);

    try process_file(allocator, file, &stream, 8);

    const exp = 
        \\[0] 'in' freq=440, amp=0.75, dur=0.25
        \\[2] 'in' freq=330, amp=0.75, dur=0.25
        \\[4] 'in' freq=440, amp=0.75, dur=0.25
        \\[6] 'in' freq=330, amp=0.75, dur=0.25
        \\
    ;

    try std.testing.expectEqualStrings(buf[0..stream.end], exp);
}
