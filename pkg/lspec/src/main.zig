const std = @import("std");
const Io = std.Io;

const lspec = @import("./root.zig");

// Определяем структуру данных
const Person = struct {
    name: []const u8,
    age: u8,
    is_student: bool,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Создаём экземпляр структуры
    const spec = lspec.specification();

    const outname = "waver-spec.json";

    // Открываем файл для записи
    var file = try std.Io.Dir.cwd().createFile(io, outname, .{});
	defer file.close(io);
	var buffer: [1024]u8 = undefined;
	var file_writer = file.writer(io, &buffer);
	try std.json.Stringify.value(spec, .{ .whitespace = .indent_2 }, &file_writer.interface);
	try file_writer.interface.flush();
}
