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

pub const SignalFilter = union(enum) {
    every: Every,
    bitShift: BitShift,
};

pub fn apply(f: SignalFilter, ctx: *Context) bool {
    return switch (f) {
        .every => |v| v.apply(ctx),
        .bitShift => |v| v.apply(ctx),
    };
}
