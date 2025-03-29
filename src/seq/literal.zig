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
    plus,
    multiply,
    sin,
    pow,
};

pub fn freeLiteral(a: Allocator, l: Literal) void {
    switch (l) {
        .list => |lst| {
            for (lst) |it| {
                freeLiteral(a, it);
            }
            a.free(lst);
        },
        else => return,
    }
}

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

pub fn dumpLiteral(prefix: []const u8, l: Literal) void {
    const debug = std.debug.print;
    if (prefix.len > 0) {
        debug("{s}: ", .{prefix});
    }
    switch (l) {
        .number => |n| debug("{} ", .{n}),
        .float => |n| debug("{} ", .{n}),
        .str => |s| debug("\"{s}\" ", .{s.string()}),
        .ident => |s| debug("{s} ", .{s.string()}),
        .list => |lst| {
            debug("[ ", .{});
            for (lst) |item| {
                dumpLiteral("", item);
            }
            debug("] ", .{});
        },
        .func => debug(".func ", .{}),
        .arg => debug(".arg ", .{}),
        .rand => debug(".rand ", .{}),
        .seq => debug(".seq ", .{}),
        .plus => debug(".plus ", .{}),
        .multiply => debug(".multiply ", .{}),
        .sin => debug(".sin ", .{}),
        .pow => debug(".pow ", .{}),
    }
    if (prefix.len > 0) {
        debug("\n", .{});
    }
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
        .plus => true,
        .multiply => true,
        .sin => true,
        .pow => true,
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
