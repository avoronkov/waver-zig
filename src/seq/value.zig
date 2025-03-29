const std = @import("std");
const primitives = @import("../pelia/primitives.zig");

const Allocator = std.mem.Allocator;

pub const Value = union(enum) {
    number: i64,
    float: f64,
    str: primitives.Path,
    ident: primitives.Ident,
    list: []Value,
};

pub fn free_value(a: Allocator, value: Value) void {
    return switch (value) {
        .list => |l| {
            for (l) |it| {
                free_value(a, it);
            }
            a.free(l);
        },
        else => return,
    };
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
