const std = @import("std");
const value = @import("./value.zig");
const Value = value.Value;
const primitives = @import("../pelia/primitives.zig");
const Context = @import("./context.zig");
const rand = @import("./rand.zig");
const literal = @import("./literal.zig");

const Allocator = std.mem.Allocator;
const Literal = literal.Literal;

const EvalError = error{emptyList,badValue,OutOfMemory};

pub fn eval(a: Allocator, ctx: *Context, expr: Literal) EvalError!Value {
    return switch (expr) {
        .number => |v| Value{ .number = v },
        .float => |v| Value{ .float = v },
        .str => |v| Value{ .str = v },
        .ident => |v| evalIdent(a, ctx, v),
        .list => |l| evalList(a, ctx, l),
        else => error.badValue,
    };
}

fn evalIdent(a: Allocator, ctx: *Context, id:primitives.Ident) EvalError!Value {
    if (std.mem.eql(u8, id.string(), "input")) {
        return Value{ .float = ctx.input };
    } else if (std.mem.eql(u8, id.string(), "time")) {
        return Value{ .float = ctx.time };
    }

    if (ctx.variables) |vars| {
        if (vars.get(id.string())) |v| {
            return eval(a, ctx, v);
        }
    }

    return Value{ .ident = id };
}

fn evalList(a: Allocator, ctx: *Context, l: []const Literal) EvalError!Value {
    if (l.len == 0) {
        return error.emptyList;
    }

    return switch (l[0]) {
        .func => evalFunc(a, ctx, l[1..]),
        .rand => evalRand(a, ctx, l[1..]),
        .seq => evalSeq(a, ctx, l[1..]),
        .plus => evalPlus(a, ctx, l[1..]),
        .multiply => evalMultiply(a, ctx, l[1..]),
        .sin => evalSin(a, ctx, l[1..]),
        .pow => evalPow(a, ctx, l[1..]),
        else => blk: {
            var res = std.ArrayListUnmanaged(Value){};
            errdefer {
                for (res.items) |it| {
                    value.free_value(a, it);
                }
                res.deinit(a);
            }

            for (l) |it| {
                const val = try eval(a, ctx, it);
                try res.append(a, val);
            }
            break :blk .{
                .list = try res.toOwnedSlice(a),
            };
        },
    };
}

// .func name arg
fn evalFunc(a: Allocator, ctx: *Context, args: []const Literal) EvalError!Value {
    if (args.len != 2) {
        std.debug.panic("evalFunc: {any}", .{ args });
    }
    const funcName = switch(args[0]) {
        .ident => |i| i.string(),
        else => std.debug.panic("evalFunc: incorrect funcName argument: {any}", .{ args[0] }),
    };

    std.debug.print("ctx.functions: {any}\n", .{ctx.functions});
    const funcBody = if (ctx.functions) |functions| 
        functions.get(funcName) orelse std.debug.panic("evalFunc unknown function: {s}", .{funcName})
    else std.debug.panic("evalFunc functions undefined", .{});

    const arg = try eval(a, ctx, args[1]);
    defer value.free_value(a, arg);

    const argLiteral = try valueToLiteral(a, arg);

    const body = try literal.substitute(a, funcBody, .arg, argLiteral);
    defer literal.freeLiteral(a, body);
    return try eval(a, ctx, body);
}

// .rand list
fn evalRand(a: Allocator, ctx: *Context, func: []const Literal) EvalError!Value {
    if (func.len != 1) {
        std.debug.panic("evalRand: {any}", .{ func });
    }
    switch (func[0]) {
        .list => |l| {
            if (isPureList(l)) {
                const i = rand.random.intRangeLessThan(usize, 0, l.len);
                return try eval(a, ctx, l[i]);
            }
        },
        else => {},
    }
    switch (try eval(a, ctx, func[1])) {
        .list => |lres| {
            const i = rand.random.intRangeLessThan(usize, 0, lres.len);
            return lres[i];
        },
        else => return error.badValue,
    }
}

// .seq counter list
fn evalSeq(a: Allocator, ctx: *Context, func: []const Literal) EvalError!Value {
    if (func.len != 2) {
        std.debug.panic("evalSeq: {any}", .{ func });
    }
    const counter: usize = @intCast(func[0].number);
    const i = ctx.getSeqCounter(counter);
    switch (func[1]) {
        .list => |l| {
            if (isPureList(l)) {
                const idx = if (i < l.len) i else 0;
                ctx.setSeqCounter(counter, idx + 1);
                return try eval(a, ctx, l[idx]);
            }
        },
        else => {},
    }
    const evaluated = try eval(a, ctx, func[1]);
    defer value.free_value(a, evaluated);
    switch (evaluated) {
        .list => |lres| {
            const idx = if (i < lres.len) i else 0;
            ctx.setSeqCounter(counter, idx + 1);
            return try value.copy_value(a, lres[idx]);
        },
        else => return error.badValue,
    }
}

fn isPureList(l: []const Literal) bool {
    if (l.len == 0) {
        return true;
    }
    return switch (l[0]) {
        .number => true,
        .float => true,
        .str => true,
        .ident => true,
        .list => true,
        .func => false,
        .arg => false,
        .rand => false,
        .seq => false,
        .plus => false,
        .multiply => false,
        .sin => false,
        .pow => false,
    };
}

fn evalPlus(a: Allocator, ctx: *Context, func: []const Literal) EvalError!Value {
    if (func.len == 0) {
        return error.emptyList;
    }

    const first = try eval(a, ctx, func[0]);
    defer value.free_value(a, first);
    switch (first) {
        .float => |f| return evalPlusType(f64, a, ctx, f, func[1..]),
        .number => |n| return evalPlusType(i64, a, ctx, n, func[1..]),
        else => return error.badValue,
    }
}

fn evalPlusType(comptime T: type, a: Allocator, ctx: *Context, first: T, args: []const Literal) EvalError!Value {
    var sum = first;
    for (args) |it| {
        const val =  try eval(a, ctx, it);
        defer value.free_value(a, val);
        switch (val) {
            .float => |f| if (T == f64) { sum += f; } else return error.badValue,
            .number => |n| if (T == i64) { sum += n; } else return error.badValue,
            .list => |l| {
                if (args.len != 1) {
                    return error.badValue;
                }
                var r = try a.alloc(Value, l.len);
                for (0.., l) |i, v| {
                    switch (v) {
                        .float => |f| if (T == f64) { r[i] = .{ .float = first + f }; } else return error.badValue,
                        .number => |n| if (T == i64) { r[i] = .{ .number = first + n }; } else return error.badValue,
                        else => return error.badValue,
                    }
                }
                return .{ .list = r };
            },
            else => return error.badValue,
        }
    }
    return if (T == f64) .{ .float = sum } else .{ .number = sum };
}

fn evalMultiply(a: Allocator, ctx: *Context, func: []const Literal) EvalError!Value {
    var res: f64 = 1;
    for (0.., func) |i, it| {
        const val =  try eval(a, ctx, it);
        defer value.free_value(a, val);
        switch (val) {
            .float => |f| res *= f,
            else => {
                std.debug.print("Not float result of {any} [{}]: {any}\n", .{it, i, val});
                return error.badValue;
            },
        }
    }
    return Value{ .float = res };
}

fn evalSin(a: Allocator, ctx: *Context, args: []const Literal) EvalError!Value {
    if (args.len != 1) {
        return error.badValue;
    }
    const val = try eval(a, ctx, args[0]);
    defer value.free_value(a, val);
    return switch (val) {
        .float => |f| .{ .float = std.math.sin(f) },
        else => error.badValue,
    };
}

fn evalPow(a: Allocator, ctx: *Context, args: []const Literal) EvalError!Value {
    if (args.len != 2) {
        return error.badValue;
    }
    const x = try eval(a, ctx, args[0]);
    defer value.free_value(a, x);
    if (std.meta.activeTag(x) != .float) {
        return error.badValue;
    }

    const y = try eval(a, ctx, args[1]);
    defer value.free_value(a, x);
    if (std.meta.activeTag(y) != .float) {
        return error.badValue;
    }

    return .{
        .float = std.math.pow(f64, x.float, y.float),
    };
}

fn valueToLiteral(a: Allocator, val: value.Value) !Literal {
    return switch (val) {
        .number => |n| Literal{ .number = n },
        .float => |f| Literal{ .float = f },
        .str => |s| Literal{ .str = s },
        .ident => |i| Literal{ .ident = i },
        .list => |lst| blk: {
            var items = try a.alloc(Literal, lst.len);
            for (0.., lst) |i, item| {
                items[i] = try valueToLiteral(a, item);
            }
            break :blk Literal{
                .list = items,
            };
        },
    };
}
