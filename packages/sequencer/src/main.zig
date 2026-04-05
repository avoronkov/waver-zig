const std = @import("std");
const Args = @import("./args.zig");
const App = @import("./app.zig");

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

    try App.process_file(allocator, args.input, stdout, args.stop);

    std.log.info("OK", .{});
}
