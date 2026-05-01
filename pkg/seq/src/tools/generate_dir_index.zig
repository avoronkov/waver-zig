const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);

    if (args.len < 3) {
        std.log.err("Not enough arguments. Usage: <dir> <output.zig>", .{});
        return error.badArgument;
    }
    const dirname = args[1];
    const outname = args[2];

    const dir = try std.Io.Dir.cwd().openDir(io, dirname, .{ .iterate = true });
    defer dir.close(io);

    var out = try std.Io.Dir.cwd().createFile(io, outname, .{});
    defer out.close(io);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = out.writer(io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    try writer.print(
        \\const std = @import("std");
        \\
        \\pub const resources = std.static_string_map.StaticStringMap([]const u8).initComptime(.{{
        \\
    , .{});

    var walker = try dir.walk(init.gpa);
    defer walker.deinit();

    while (try walker.next(io)) |item| {
        if (item.kind != .file) {
            continue;
        }

        const file_data = try dir.readFileAlloc(io, item.path, init.gpa, .unlimited);

        // std.debug.print("{s}\n", .{item.path});
        try writer.print("    .{{ \"{s}\", &[_]u8{any} }},\n", .{item.path, file_data});
        init.gpa.free(file_data);
    }
    try writer.print(
        \\}});
        \\
    , .{});
    try writer.flush();
}
