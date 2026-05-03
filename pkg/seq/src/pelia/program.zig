const std = @import("std");
const Signaler = @import("../seq/signaler.zig");
const literal = @import("../seq/literal.zig");
const Instrument = @import("../instrument.zig");

const Allocator = std.mem.Allocator;
const Literal = literal.Literal;

const Self = @This();

allocator: Allocator,
mtime: ?std.Io.Timestamp = null,
instruments: std.StringHashMapUnmanaged(Instrument) = .empty,
signalers: std.ArrayListUnmanaged(Signaler) = .empty,
seqCounters: i64 = 0,
variables: std.StringHashMapUnmanaged(Literal) = .empty,
functions: std.StringHashMapUnmanaged(Literal) = .empty,
user_signalers: std.StringHashMapUnmanaged(Signaler) = .empty,
scaleFrequencies: []const f64 = &[_]f64{},
tempo: ?f64 = null,
stop: ?i64 = null,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
    };
}

pub fn deinit(self: *Self) void {
    // deinit instruments
    var instIter = self.instruments.iterator();
    while (instIter.next()) |pair| {
        self.allocator.free(pair.key_ptr.*);
        pair.value_ptr.deinit();
    }
    self.instruments.deinit(self.allocator);

    // deinit signalers
    for (self.signalers.items) |*s| {
        s.deinit();
    }
    self.signalers.deinit(self.allocator);

    // deinit variables
    var varIter = self.variables.iterator();
    while (varIter.next()) |pair| {
        self.allocator.free(pair.key_ptr.*);
        pair.value_ptr.deinit(self.allocator);
    }
    self.variables.deinit(self.allocator);

    // deinit functions
    var funcIter = self.functions.iterator();
    while (funcIter.next()) |pair| {
        self.allocator.free(pair.key_ptr.*);
        pair.value_ptr.deinit(self.allocator);
    }
    self.functions.deinit(self.allocator);

    // deinit user_signalers
    var sigIter = self.user_signalers.iterator();
    while (sigIter.next()) |pair| {
        self.allocator.free(pair.key_ptr.*);
        pair.value_ptr.deinit();
    }
    self.user_signalers.deinit(self.allocator);
}
