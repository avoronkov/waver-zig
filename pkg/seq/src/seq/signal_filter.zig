const Context = @import("./context.zig");

pub const Every = struct {
    n: i64,

    pub fn apply(self: Every, ctx: *Context) bool {
        return @rem(ctx.bit, self.n) == 0;
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
    bitShift: BitShift,
    moreOrEqual: MoreOrEqual,
    lessThan: LessThan,
};

pub fn apply(f: SignalFilter, ctx: *Context) bool {
    return switch (f) {
        .every => |v| v.apply(ctx),
        .bitShift => |v| v.apply(ctx),
        .lessThan => |v| v.apply(ctx),
        .moreOrEqual => |v| v.apply(ctx),
    };
}
