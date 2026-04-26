const std = @import("std");
const signal = @import("./signal.zig");
const signal_filter = @import("./signal_filter.zig");
const signal_func = @import("./signal_func.zig");
const Context = @import("./context.zig");

const SignalFunc = signal_func.SignalFunc;
const Signals = signal_func.Signals;

const SignalList = std.ArrayListUnmanaged(signal.Signal);

const Self = @This();

const Allocator = std.mem.Allocator;
const SignalFilters = std.ArrayListUnmanaged(signal_filter.SignalFilter);

const SignalFuncLike = union(enum) {
    func: SignalFunc,
    signaler: []const u8,
};
const SignalFuncs = std.ArrayListUnmanaged(SignalFuncLike);

allocator: Allocator,
signal_filters: SignalFilters,
signal_funcs: SignalFuncs,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .signal_filters = .empty,
        .signal_funcs = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.signal_filters.deinit(self.allocator);

    for (self.signal_funcs.items) |*f| {
        switch (f.*) {
            .func => |*fun| fun.deinit(self.allocator),
            .signaler => |sg| self.allocator.free(sg),
        }
    }
    self.signal_funcs.deinit(self.allocator);
}

pub fn add_filter(self: *Self, f: signal_filter.SignalFilter) !void {
    try self.signal_filters.append(self.allocator, f);
}

pub fn add_func(self: *Self, f: SignalFunc) !void {
    try self.signal_funcs.append(self.allocator, .{ .func =  f });
}

pub fn add_signaler(self: *Self, name: []const u8) !void {
    try self.signal_funcs.append(self.allocator, .{ .signaler =  try self.allocator.dupe(u8, name) });
}

const SignalsErrors = error{OutOfMemory,emptyList,badValue,badAmplitude,badDuration,badFrequency,badInstrument};

pub fn signals(self: Self, ctx: *Context) SignalsErrors!?Signals {
    for (self.signal_filters.items) |filt| {
        if (!signal_filter.apply(filt, ctx)) {
            return null;
        }
    }
    var res: SignalList = .empty;
    errdefer res.deinit(self.allocator);

    for (self.signal_funcs.items) |f| {
        try self.handle_signal(&res, f, ctx);
    }
    return try res.toOwnedSlice(self.allocator);
}

fn handle_signal(self: Self, res: *SignalList, f: SignalFuncLike, ctx: *Context) SignalsErrors!void {
    switch (f) {
        .func => |fun| {
            const sigs = try fun.eval(self.allocator, ctx);
            defer self.allocator.free(sigs);
            try res.appendSlice(self.allocator, sigs);
        },
        .signaler => |name| {
            if (ctx.user_signalers) |us| {
                if (us.get(name)) |sig| {
                    const sub_signals = try sig.signals(ctx);
                    if (sub_signals) |sigs| {
                        defer self.allocator.free(sigs);
                        try res.appendSlice(self.allocator, sigs);
                    }
                }
            }
        },
    }
}
