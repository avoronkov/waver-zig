const std = @import("std");
const lisp = @import("./lisp.zig");
const Literal = @import("./literal.zig").Literal;

const Allocator = std.mem.Allocator;
const SeqCounters = std.ArrayListUnmanaged(usize);
const Variables = std.StringHashMapUnmanaged(Literal);

const Self = @This();

allocator: Allocator,

seqCounters: SeqCounters,
variables: ?*const Variables,
functions: ?*const Variables,

scaleFrequencies: []const f64,

bit: i64 = 0,
realBit: i64 = 0,

time: f64 = 0,
input: f64 = 0,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .seqCounters = .{},
        .variables = null,
        .functions = null,
        .scaleFrequencies = &[_]f64{},
    };
}

pub fn deinit(self: *Self) void {
    self.seqCounters.deinit(self.allocator);
}

pub fn initSeqCounters(self: *Self, n: usize) !void {
    if (self.seqCounters.items.len > n) {
        self.seqCounters.shrinkAndFree(self.allocator, n);
    } else if (self.seqCounters.items.len < n) {
        const prev_len = self.seqCounters.items.len;
        try self.seqCounters.resize(self.allocator, n);
        for (prev_len..n) |i| {
            self.seqCounters.items[i] = 0;
        }
    }
}

pub fn getSeqCounter(self: Self, index: usize) usize {
    return self.seqCounters.items[index];
}

pub fn setSeqCounter(self: *Self, index: usize, value: usize) void {
    self.seqCounters.items[index] = value;
}
