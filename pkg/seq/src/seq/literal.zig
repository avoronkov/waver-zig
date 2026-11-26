const std = @import("std");
const primitives = @import("../pelia/primitives.zig");

const Allocator = std.mem.Allocator;

pub const Literal = union(enum) {
    number: i64,
    float: f64,
    str: primitives.Path,
    ident: primitives.Ident,
    list: []const Literal,
    func,
    arg,
    rand,
    seq,
    repeat,
    loop,
    plus,
    minus,
    multiply,
    divide,
    sin,
    cos,
    pow,
    value_of,
    ifelse,
    eq,
    gt,
    ge,
    lt,
    le,
    land,
    lor,
    lnot,

    pub fn deinit(self: *const Literal, a: Allocator) void {
        switch (self.*) {
            .list => |*lst| {
                for (lst.*) |it| {
                    it.deinit(a);
                }
                a.free(lst.*);
            },
            else => return,
        }
    }

    pub fn format(self: Literal, writer: *std.Io.Writer) !void {
        try switch (self) {
            .number => |n| writer.print(".number={}", .{n}),
            .float => |n| writer.print(".float={}", .{n}),
            .str => |s| writer.print(".str={s}", .{s.string()}),
            .ident => |i| writer.print(".ident={s}", .{i.string()}),
            .list => |l| {
                try writer.print(".list=[ ", .{});
                for (l) |it| {
                    try writer.print("{f} ", .{it});
                }
                try writer.print("]", .{});
            },
            .func => writer.print(".func", .{}),
            .arg => writer.print(".arg", .{}),
            .rand => writer.print(".rand", .{}),
            .seq => writer.print(".seq", .{}),
            .repeat => writer.print(".repeat", .{}),
            .loop => writer.print(".loop", .{}),
            .plus => writer.print(".plus", .{}),
            .minus => writer.print(".minus", .{}),
            .multiply => writer.print(".multiply", .{}),
            .divide => writer.print(".divide", .{}),
            .sin => writer.print(".sin", .{}),
            .cos => writer.print(".cos", .{}),
            .pow => writer.print(".pow", .{}),
            .value_of => writer.print(".balue_of", .{}),
            .ifelse => writer.print(".if", .{}),
            .eq => writer.print(".eq", .{}),
            .gt => writer.print(".gt", .{}),
            .ge => writer.print(".ge", .{}),
            .lt => writer.print(".lt", .{}),
            .le => writer.print(".le", .{}),
            .land => writer.print(".and", .{}),
            .lor => writer.print(".or", .{}),
            .lnot => writer.print(".not", .{}),
        };
    }
};

pub fn copyLiteral(a: Allocator, l: Literal) !Literal {
    return switch (l) {
        .list => |lst| blk: {
            var res = try a.alloc(Literal, lst.len);
            for (0.., lst) |i, item| {
                res[i] = try copyLiteral(a, item);
            }
            break :blk .{ .list = res };
        },
        else => l,
    };
}

pub fn eql(a: Literal, b: Literal) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) {
        return false;
    }
    return switch (a) {
        .number => a.number == b.number,
        .float => a.float == b.float,
        .str => std.mem.eql(u8, a.str.string(), b.str.string()),
        .ident => std.mem.eql(u8, a.ident.string(), b.ident.string()),
        .list => std.debug.panic("NIY", .{}),
        .func => true,
        .arg => true,
        .rand => true,
        .seq => true,
        .repeat => true,
        .loop => true,
        .plus => true,
        .minus => true,
        .multiply => true,
        .divide => true,
        .sin => true,
        .cos => true,
        .pow => true,
        .value_of => true,
        .ifelse => true,
        .eq => true,
        .le => true,
        .lt => true,
        .ge => true,
        .gt => true,
        .land => true,
        .lor => true,
        .lnot => true,
    };
}

pub fn substitute(a: Allocator, l: Literal, from: Literal, to: Literal) !Literal {
    if (eql(l, from)) {
        return to;
    }
    return switch (l) {
        .list => |lst| blk: {
            var items = try a.alloc(Literal, lst.len);
            for (0.., lst) |i, it| {
                items[i] = try substitute(a, it, from, to);
            }
            break :blk .{
                .list = items,
            };
        },
        else => l,
    };
}
