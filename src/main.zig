const std = @import("std");
const Tape = @import("./tape.zig");
const Beeper = @import("./beeper.zig");
const rand = @import("./seq/rand.zig");
const pulse = @import("./pulse.zig");
const Args = @import("./args.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rand.init();

    const args = try Args.init(allocator);
    defer args.deinit();

    if (args.input.len == 0) {
        std.debug.print("No input file specified.\n", .{});
        return error.noInput;
    }

    const s = try pulse.paSimpleNew();
    defer pulse.paSimpleFree(s);

    var tape = Tape.init(allocator);
    defer tape.deinit();

    var beeper = try Beeper.init(allocator, args.input, &tape, 250 * 1000);
    defer beeper.deinit();

    var thread = try std.Thread.spawn(.{}, Beeper.run, .{&beeper});
    defer thread.join();

    try pulse.play(s, &tape);

    try pulse.paSimpleDrain(s);

    std.log.info("OK", .{});
}
