const std = @import("std");
const pulse = @import("./pulse.zig");
const Args = @import("./args.zig");

const sequencer = @import("sequencer");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try Args.init(allocator);
    defer args.deinit();

    if (args.input.len == 0) {
        std.log.err("No input file specified.\n", .{});
        return error.noInput;
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var app = try sequencer.App.init(allocator, args.input, stdout, args.stop);
    defer app.deinit();

    const s = try pulse.paSimpleNew();
    defer pulse.paSimpleFree(s);

    var t = try app.run();

    try pulse.play(s, &app.tape);

    t.join();

    try pulse.paSimpleDrain(s);

    std.log.info("OK", .{});
}
