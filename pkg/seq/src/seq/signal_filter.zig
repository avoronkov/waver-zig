const std = @import("std");
const Context = @import("./context.zig");

pub const Every = struct {
    n: i64,

    pub fn apply(self: Every, ctx: *Context) bool {
        ctx.duration_bits = self.n;
        return @rem(ctx.bit, self.n) == 0;
    }
};

pub const EveryList = struct {
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

    pub fn deinit(self: *EveryList, a: std.mem.Allocator) void {
        a.free(self.args);
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

const EuclidianFirstV1 = struct {
    pulses: i64,
    steps: i64,

    pub fn init(a: std.mem.Allocator, pulses: i64, steps: i64) !EuclidianFirstV1 {
        _ = a;
        return .{
            .pulses = pulses,
            .steps = steps,
        };
    }

    pub fn deinit(self: EuclidianFirstV1, a: std.mem.Allocator) void {
        _ = self;
        _ = a;
    }

    pub fn apply(self: EuclidianFirstV1, ctx: *Context) bool {
        var bucket: i64 = 0;
        var result = false;
        const bit: usize = @intCast(@rem(ctx.bit, self.steps));
        for (0..bit+1) |_| {
            if (bucket >= 0) {
                bucket -= self.steps;
                result = true;
            } else {
                result = false;
            }
            bucket += self.pulses;
        }
        return result;
    }
};

const EuclidianFirstV2 = struct {
    pulses: i64,
    steps: i64,

    durs: []i64,

    pub fn init(a: std.mem.Allocator, pulses: i64, steps: i64) !EuclidianFirstV2 {
        var durs = try a.alloc(i64, @intCast(steps));
        var bucket: i64 = 0;
        var prev: usize = 0;
        for (durs, 0..) |_, i| {
            durs[i] = 0;
            if (bucket >= 0) {
                bucket -= steps;
                if (i > 0) {
                    durs[prev] = @intCast(i - prev);
                    prev = i;
                }
            }
            bucket += pulses;
        }
        if (pulses > 0) {
            const usteps: usize = @intCast(steps);
            durs[prev] = @intCast(usteps - prev);
        }
        return .{
            .pulses = pulses,
            .steps = steps,
            .durs = durs,
        };
    }

    pub fn deinit(self: EuclidianFirstV2, a: std.mem.Allocator) void {
        a.free(self.durs);
    }

    pub fn apply(self: EuclidianFirstV2, ctx: *Context) bool {
        const bit: usize = @intCast(@rem(ctx.bit, self.steps));
        if (self.durs[bit] > 0) {
            ctx.duration_bits = self.durs[bit];
            return true;
        }
        return false;
    }
};

test "EuclidianFirst [V1] benchmark" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const clock = std.Io.Clock.real;

    const start = clock.now(io);

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const eu = EuclidianFirstV1{ .pulses = 23, .steps = 53 };

    for (0..10000) |i| {
        ctx.bit = @intCast(i);
        _ = eu.apply(&ctx);
    }

    const dur = start.untilNow(io, clock);
    const ns = dur.toNanoseconds();
    std.debug.print("EuclidianFirst [V1] benchmark: {}ns per op\n", .{@divFloor(ns, 10000)});
}

test "EuclidianFirst [V2] benchmark" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const clock = std.Io.Clock.real;

    const start = clock.now(io);

    var ctx = Context.init(allocator);
    defer ctx.deinit();

    const eu = try EuclidianFirstV2.init(allocator, 23,  53);
    defer eu.deinit(allocator);

    for (0..10000) |i| {
        ctx.bit = @intCast(i);
        _ = eu.apply(&ctx);
    }

    const dur = start.untilNow(io, clock);
    const ns = dur.toNanoseconds();
    std.debug.print("EuclidianFirst [V2] benchmark: {}ns per op\n", .{@divFloor(ns, 10000)});
}

test "EuclidianFirst [V2] 3 / 8" {
    const allocator = std.testing.allocator;
    const eu = try EuclidianFirstV2.init(allocator, 3, 8);
    defer eu.deinit(allocator);

    try std.testing.expectEqualSlices(i64, eu.durs, &.{3, 0, 0, 3, 0, 0, 2, 0});
}

test "EuclidianFirst [V2] 4 / 4" {
    const allocator = std.testing.allocator;
    const eu = try EuclidianFirstV2.init(allocator, 4, 4);
    defer eu.deinit(allocator);

    try std.testing.expectEqualSlices(i64, eu.durs, &.{1, 1, 1, 1});
}

test "EuclidianFirst [V2] 1 / 4" {
    const allocator = std.testing.allocator;
    const eu = try EuclidianFirstV2.init(allocator, 1, 4);
    defer eu.deinit(allocator);

    try std.testing.expectEqualSlices(i64, eu.durs, &.{4, 0, 0, 0});
}

test "EuclidianFirst [V2] 0 / 4" {
    const allocator = std.testing.allocator;
    const eu = try EuclidianFirstV2.init(allocator, 0, 4);
    defer eu.deinit(allocator);

    try std.testing.expectEqualSlices(i64, eu.durs, &.{0, 0, 0, 0});
}

pub const EuclidianFirst = EuclidianFirstV2;

pub const SignalFilter = union(enum) {
    every: Every,
    everyList: EveryList,
    bitShift: BitShift,
    moreOrEqual: MoreOrEqual,
    lessThan: LessThan,
    euclidianFirst: EuclidianFirst,

    pub fn deinit(self: *SignalFilter, a: std.mem.Allocator) void {
        switch (self.*) {
            .everyList => |*l| l.deinit(a),
            .euclidianFirst => |*eu| eu.deinit(a),
            else => {},
        }
    }

    pub fn apply(f: SignalFilter, ctx: *Context) bool {
        return switch (f) {
            .every => |v| v.apply(ctx),
            .everyList => |v| v.apply(ctx),
            .bitShift => |v| v.apply(ctx),
            .lessThan => |v| v.apply(ctx),
            .moreOrEqual => |v| v.apply(ctx),
            .euclidianFirst => |v| v.apply(ctx),
        };
    }
};
