const std = @import("std");
const Signaler = @import("../seq/signaler.zig");
const lisp = @import("../seq/lisp.zig");
const literal = @import("../seq/literal.zig");
const Instrument = @import("../instrument.zig");
const primitives = @import("./primitives.zig");

const Allocator = std.mem.Allocator;
const Literal = literal.Literal;
const freeLiteral = literal.freeLiteral;

const Self = @This();

allocator: Allocator,
mtime: i128 = 0,
instruments: std.StringHashMapUnmanaged(Instrument) = .{},
signalers: std.ArrayListUnmanaged(Signaler) = .{},
seqCounters: i64 = 0,
variables: std.StringHashMapUnmanaged(Literal) = .{},
scaleFrequencies: []const f64 = &[_]f64{},

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
        freeLiteral(self.allocator, pair.value_ptr.*);
    }
    self.variables.deinit(self.allocator);
}
