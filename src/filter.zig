const std = @import("std");
const Chain = @import("./chain.zig");
const Note = @import("./note.zig");
const EofError = @import("./wave.zig").EofError;
const lisp = @import("./seq/lisp.zig");
const literal = @import("./seq/literal.zig");
const Context = @import("./seq/context.zig");
const value = @import("./seq/value.zig");

const Allocator = std.mem.Allocator;
const Literal = literal.Literal;

pub const Am = struct {
    freq: f64,

    pub fn apply(self: Am, chain: Chain, n: i32, t: f64, note: Note) EofError!f64 {
        const x = 2 * std.math.pi * t * self.freq;
        const am = std.math.sin(x);
        const v = try chain.value_of(n-1, t, note);
        return am * v;
    }
};

const TestChain = struct {
    pub fn value_of(self: *const TestChain, n: i32, t: f64, note: Note) EofError!f64 {
        _ = self;
        _ = n;
        _ = t;
        _ = note;
        return 0.5;
    }
};

test "AM benchmark" {
    const testChain = TestChain{};
    const chain = Chain.init(&testChain);
    const am = Am{ .freq = 16.0 };
    const note = Note{
        .freq = 440,
        .amp = 0.5,
        .dur = 0.25,
    };

    const start = std.time.nanoTimestamp();
    for (0..10000) |_| {
        _ = am.apply(chain, 1, 2.0, note) catch unreachable;
    }
    const finish = std.time.nanoTimestamp();
    const ns = @divFloor(finish - start, 10000);
    std.debug.print("AM benchmark: {}ns per op\n", .{ns});
}

pub const Exp = struct {
    value: f64,

    pub fn apply(self: Exp, chain: Chain, n: i32, t: f64, note: Note) EofError!f64 {
        const v = try chain.value_of(n-1, t, note);
        return std.math.pow(f64, v, self.value);
    }
};

test "Exp benchmark" {
    const testChain = TestChain{};
    const chain = Chain.init(&testChain);
    const exp = Exp{ .value = 4.0 };
    const note = Note{
        .freq = 440,
        .amp = 0.5,
        .dur = 0.25,
    };

    const start = std.time.nanoTimestamp();
    for (0..10000) |_| {
        _ = exp.apply(chain, 1, 2.0, note) catch unreachable;
    }
    const finish = std.time.nanoTimestamp();
    const ns = @divFloor(finish - start, 10000);
    std.debug.print("Exp benchmark: {}ns per op\n", .{ns});
}


pub const LispCode = struct {
    allocator: Allocator,
    code: Literal,

    pub fn init(a: Allocator, code: Literal) LispCode {
        return .{
            .allocator = a,
            .code = code,
        };
    }

    pub fn deinit(self: *LispCode) void {
        literal.freeLiteral(self.allocator, self.code);
    }

    pub fn copy(self: *const LispCode, a: Allocator) !LispCode {
        const lit = try literal.copyLiteral(a, self.code);
        return .{
            .allocator = a,
            .code = lit,
        };
    }

    pub fn apply(self: *const LispCode, chain: Chain, n: i32, t: f64, note: Note) EofError!f64 {
        const v = try chain.value_of(n-1, t, note);
        var ctx = Context.init(self.allocator);
        defer ctx.deinit();
        ctx.input = v;
        ctx.time = t;
        const res = lisp.eval(self.allocator, &ctx, self.code) catch |e| {
            std.debug.print("Lisp code failure: {!}\n", .{e});
            return error.Eof;
        };
        defer value.free_value(self.allocator, res);
        switch (res) {
            .float => |f| return f,
            else => {
                std.debug.print("Lisp not float return: {any}\n", .{res});
                return error.Eof;
            },
        }
    }
};

test "LispCode benchmark" {
    const primitives = @import("./pelia/primitives.zig");
    const testChain = TestChain{};
    const chain = Chain.init(&testChain);
    const note = Note{
        .freq = 440,
        .amp = 0.5,
        .dur = 0.25,
    };
    const code = Literal{
        .list = &[_]Literal{
           .pow,
           Literal{ .ident = try primitives.Ident.init("input") },
           Literal{ .float = 4.0 },
        },
    };

    const codeFilter = LispCode.init(std.testing.allocator, code);

    const start = std.time.nanoTimestamp();
    for (0..10000) |_| {
        _ = codeFilter.apply(chain, 1, 2.0, note) catch unreachable;
    }
    const finish = std.time.nanoTimestamp();
    const ns = @divFloor(finish - start, 10000);
    std.debug.print("Exp benchmark [lisp]: {}ns per op\n", .{ns});
}

pub const Filter = union(enum) {
    am: Am,
    exp: Exp,
    code: LispCode,
};

pub fn filter_apply(f: Filter, chain: Chain, n: i32, t: f64, note: Note) EofError!f64 {
    return switch(f) {
        .am => |v| v.apply(chain, n, t, note),
        .exp => |v| v.apply(chain, n, t, note),
        .code => |v| v.apply(chain, n, t, note),
    };
}

pub fn free_filter(f: *Filter) void {
    switch(f.*) {
        .am => {},
        .exp => {},
        .code => |*c| c.deinit(),
    }
}

pub fn copy_filter(a: Allocator, f: Filter) !Filter {
    return switch (f) {
        .am => |v| .{ .am = v },
        .exp => |v| .{ .exp = v },
        .code => |v| .{ .code = try v.copy(a) },
    };
}
