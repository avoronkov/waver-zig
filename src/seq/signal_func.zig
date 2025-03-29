const std = @import("std");
const Signal = @import("./signal.zig").Signal;
const value = @import("./value.zig");
const Context = @import("./context.zig");
const primitives = @import("../pelia/primitives.zig");
const lisp = @import("./lisp.zig");
const literal = @import("./literal.zig");
const Literal = literal.Literal;

const Ident = primitives.Ident;

const Allocator = std.mem.Allocator;

pub const Signals = []Signal;

const SignalList = std.ArrayListUnmanaged(Signal);

pub const SignalError = error{badInstrument,badFrequency,badAmplitude,badDuration};

pub const SignalFunc = struct {
    inst: Literal,
    freq: Literal,
    amplitude: Literal,
    duration_bits: Literal,

    pub fn eval(self: SignalFunc, a: Allocator, ctx: *Context) !Signals {
        var res = SignalList{};
        errdefer res.deinit(a);

        const instVal = try lisp.eval(a, ctx, self.inst);
        defer value.free_value(a, instVal);
        switch (instVal) {
            .ident => |v| try self.evalFreqAmpDur(a, ctx, v, &res),
            .list => |l| {
                for (l) |v| {
                    switch (v) {
                        .ident => |in| try self.evalFreqAmpDur(a, ctx, in, &res),
                        else => return error.badInstrument,
                    }
                }

            },
            else => return error.badInstrument,
        }
        return try res.toOwnedSlice(a);
    }

    fn evalFreqAmpDur(self: SignalFunc, a: Allocator, ctx: *Context, inst: Ident, res: *SignalList) !void {
        const freqVal = try lisp.eval(a, ctx, self.freq);
        defer value.free_value(a, freqVal);
        switch (freqVal) {
            .float => |v| try self.evalAmpDur(a, ctx, inst, v, res),
            .number => |n| blk: {
                const idx: usize = @intCast(n);
                const freq = ctx.scaleFrequencies[idx];
                break :blk try self.evalAmpDur(a, ctx, inst, freq, res);
            },
            .list => |l| {
                for (l) |v| {
                    switch (v) {
                        .float => |f| try self.evalAmpDur(a, ctx, inst, f, res),
                        .number => |n| blk: {
                            const idx: usize = @intCast(n);
                            const freq = ctx.scaleFrequencies[idx];
                            break :blk try self.evalAmpDur(a, ctx, inst, freq, res);
                        },
                        else => {
                            std.debug.print("badFrequency [1]: {any}\n", .{v});
                            return error.badFrequency;
                        },
                    }
                }
            },
            else => {
                std.debug.print("badFrequency [2]: {any}\n", .{freqVal});
                return error.badFrequency;
            },
        }
    }

    fn evalAmpDur(self: SignalFunc, a: Allocator, ctx: *Context, inst: Ident, freq: f64, res: *SignalList) !void {
        const ampVal = try lisp.eval(a, ctx, self.amplitude);
        defer value.free_value(a, ampVal);
        const amp = switch (ampVal) {
            .float => |v| v,
            .number => |v| blk: { const f: f64 = @floatFromInt(v);  break :blk f / 16.0; },
            else => return error.badAmplitude,
        };

        const durVal = try lisp.eval(a, ctx, self.duration_bits);
        defer value.free_value(a, durVal);
        const dur = switch (durVal) {
            .number => |v| v,
            else => return error.badDuration,
        };

        const sig: Signal = .{
            .instrument = inst,
            .freq = freq,
            .amplitude = amp,
            .duration_bits = dur,
        };
        try res.append(a, sig);
    }

    pub fn deinit(self: *SignalFunc, allocator: Allocator) void {
        literal.freeLiteral(allocator, self.inst);
        literal.freeLiteral(allocator, self.freq);
        literal.freeLiteral(allocator, self.amplitude);
        literal.freeLiteral(allocator, self.duration_bits);
    }
};
