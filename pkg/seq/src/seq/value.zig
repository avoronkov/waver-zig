const std = @import("std");
const primitives = @import("../pelia/primitives.zig");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    number: i64,
    float: f64,
    str: primitives.Path,
    ident: primitives.Ident,
    list: []Value,

    pub fn deinit(self: *const Value, a: Allocator) void {
        switch (self.*) {
            .list => |l| {
                for (l) |it| {
                    it.deinit(a);
                }
                a.free(l);
            },
            else => return,
        }
    }

    pub fn format(self: Value, writer: *std.Io.Writer) !void {
        switch (self) {
            .number => |n| try writer.print(".number={}", .{n}),
            .float => |f| try writer.print(".number={}", .{f}),
            .str => |s| try writer.print(".str={s}", .{ s.string() }),
            .ident => |i| try writer.print(".ident={s}", .{i.string()}),
            .list => |l| {
                try writer.print(".list=[ ", .{});
                for (l) |it| {
                    try writer.print("{f} ", .{it});
                }
                try writer.print("]", .{});
            },
        }
    }
};

pub fn free_value(a: Allocator, value: Value) void {
    value.deinit(a);
}

pub fn copy_value(a: Allocator, value: Value) !Value {
    return switch (value) {
        .number => value,
        .float => value,
        .str => value,
        .ident => value,
        .list => |l| blk: {
            var values = try a.alloc(Value, l.len);
            errdefer a.free(values);
            for (0.., l) |i, it| {
                values[i] = try copy_value(a, it);
                errdefer free_value(it);
            }
            break :blk Value{ .list = values };
        },
    };
}
