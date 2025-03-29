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
const SignalFuncs = std.ArrayListUnmanaged(SignalFunc);

allocator: Allocator,
signal_filters: SignalFilters,
signal_funcs: SignalFuncs,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .signal_filters = SignalFilters{},
        .signal_funcs = SignalFuncs{},
    };
}

pub fn deinit(self: *Self) void {
    self.signal_filters.deinit(self.allocator);

    for (self.signal_funcs.items) |*f| {
        f.deinit(self.allocator);
    }
    self.signal_funcs.deinit(self.allocator);
}

pub fn add_filter(self: *Self, f: signal_filter.SignalFilter) !void {
    try self.signal_filters.append(self.allocator, f);
}

pub fn add_func(self: *Self, f: SignalFunc) !void {
    try self.signal_funcs.append(self.allocator, f);
}

pub fn signals(self: Self, ctx: *Context) !?Signals {
    for (self.signal_filters.items) |filt| {
        if (!signal_filter.apply(filt, ctx)) {
            return null;
        }
    }
    var res = SignalList{};
    errdefer res.deinit(self.allocator);

    for (self.signal_funcs.items) |f| {
        try self.handle_signal(&res, f, ctx);
    }
    return try res.toOwnedSlice(self.allocator);
}

fn handle_signal(self: Self, res: *SignalList, f: SignalFunc, ctx: *Context) !void {
    const sigs = try f.eval(self.allocator, ctx);
    defer self.allocator.free(sigs);
    try res.appendSlice(self.allocator, sigs);
}
