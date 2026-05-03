const std = @import("std");
const Context = @import("./context.zig");

pub const Every = struct {
    n: i64,

    pub fn apply(self: Every, ctx: *Context) bool {
        return @rem(ctx.bit, self.n) == 0;
    }
};

pub const EveryList = struct {
    allocator: std.mem.Allocator,
    args: []i64,

    pub fn apply(self: EveryList, ctx: *Context) bool {
        var loop: i64 = 0;
        for (self.args) |arg| {
            loop += arg;
        }
        const x = @rem(ctx.bit, loop);
        var s: i64 = 0;
        for (self.args) |arg| {
           if (x == s) {
               return true;
           }
           s += arg;
        }
        return false;
    }

    pub fn deinit(self: *EveryList) void {
        self.allocator.free(self.args);
    }
};

pub const BitShift = struct {
    n: i64,

    pub fn apply(self: BitShift, ctx: *Context) bool {
        ctx.bit -= self.n;
        return true;
    }
};

pub const MoreOrEqual = struct {
    n: i64,

    pub fn apply(self: MoreOrEqual, ctx: *Context) bool {
        return ctx.bit >= self.n;
    }
};

pub const LessThan = struct {
    n: i64,

    pub fn apply(self: LessThan, ctx: *Context) bool {
        return ctx.bit < self.n;
    }
};

pub const SignalFilter = union(enum) {
    every: Every,
    everyList: EveryList,
    bitShift: BitShift,
    moreOrEqual: MoreOrEqual,
    lessThan: LessThan,

    pub fn deinit(self: *SignalFilter) void {
        switch (self.*) {
            .everyList => |*l| l.deinit(),
            else => {},
        }
    }
};

pub fn apply(f: SignalFilter, ctx: *Context) bool {
    return switch (f) {
        .every => |v| v.apply(ctx),
        .everyList => |v| v.apply(ctx),
        .bitShift => |v| v.apply(ctx),
        .lessThan => |v| v.apply(ctx),
        .moreOrEqual => |v| v.apply(ctx),
    };
}
