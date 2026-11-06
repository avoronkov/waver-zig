const std = @import("std");
const Literal = @import("./literal.zig").Literal;
const Signaler = @import("../seq/signaler.zig");
const Chain = @import("../chain.zig");
const Note = @import("../note.zig");
const Value = @import("./value.zig").Value;

const Allocator = std.mem.Allocator;
const Counters = std.ArrayListUnmanaged(usize);
const Variables = std.StringHashMapUnmanaged(Literal);

const Self = @This();

allocator: Allocator,

seqCounters: Counters = .empty,

repeatCounters: Counters = .empty,
repeatValues: std.ArrayListUnmanaged(?Value) = .empty,

loopCounters: Counters = .empty,
loopValues: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Value)) = .empty,

variables: ?*const Variables = null,
functions: ?*const Variables = null,
user_signalers: ?*const std.StringHashMapUnmanaged(Signaler) = null,

scaleFrequencies: []const f64,
notes_names: []const []const u8,

bit: i64 = 0,
realBit: i64 = 0,

time: f64 = 0,
input: f64 = 0,

chain: ?*const Chain = null,
n_chain: ?i32 = null,
note: ?Note = null,

// If duration bits are set by filters.
duration_bits: ?i64 = null,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .scaleFrequencies = &[_]f64{},
        .notes_names = &[_][]u8{},
    };
}

pub fn deinit(self: *Self) void {
    self.seqCounters.deinit(self.allocator);
    self.repeatCounters.deinit(self.allocator);

    for (self.repeatValues.items) |v| {
        if (v) |val| {
            val.deinit(self.allocator);
        }
    }
    self.repeatValues.deinit(self.allocator);

    for (self.loopValues.items) |*values| {
        for (values.items) |v| {
            v.deinit(self.allocator);
        }
        values.deinit(self.allocator);
    }
    self.loopValues.deinit(self.allocator);
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

pub fn initRepeatCounters(self: *Self, n: usize) !void {
    if (self.repeatCounters.items.len > n) {
        self.repeatCounters.shrinkAndFree(self.allocator, n);
    } else if (self.repeatCounters.items.len < n) {
        const prev_len = self.repeatCounters.items.len;
        try self.repeatCounters.resize(self.allocator, n);
        for (prev_len..n) |i| {
            self.repeatCounters.items[i] = 0;
        }
    }

    if (self.repeatValues.items.len > n) {
        self.repeatValues.shrinkAndFree(self.allocator, n);
    } else if (self.repeatValues.items.len < n) {
        const prev_len = self.repeatValues.items.len;
        try self.repeatValues.resize(self.allocator, n);
        for (prev_len..n) |i| {
            self.repeatValues.items[i] = null;
        }
    }
}

pub fn initLoopCounters(self: *Self, n: usize) !void {
    if (self.loopCounters.items.len > n) {
        self.loopCounters.shrinkAndFree(self.allocator, n);
    } else if (self.loopCounters.items.len < n) {
        const prev_len = self.loopCounters.items.len;
        try self.loopCounters.resize(self.allocator, n);
        for (prev_len..n) |i| {
            self.loopCounters.items[i] = 0;
        }
    }

    if (self.loopValues.items.len > n) {
        self.loopValues.shrinkAndFree(self.allocator, n);
    } else if (self.loopValues.items.len < n) {
        const prev_len = self.loopValues.items.len;
        try self.loopValues.resize(self.allocator, n);
        for (prev_len..n) |i| {
            self.loopValues.items[i] = .empty;
        }
    }
}


pub fn getSeqCounter(self: Self, index: usize) usize {
    return self.seqCounters.items[index];
}

pub fn setSeqCounter(self: *Self, index: usize, value: usize) void {
    self.seqCounters.items[index] = value;
}

pub fn getRepeatCounter(self: Self, index: usize) usize {
    return self.repeatCounters.items[index];
}

pub fn getRepeatValue(self: Self, index: usize) ?Value {
    return self.repeatValues.items[index];
}

pub fn setRepeatItem(self: *Self, index: usize, count: usize, value: Value) void {
    self.repeatCounters.items[index] = count;
    self.repeatValues.items[index] = value;
}

pub fn getLoopSize(self: Self, index: usize) usize {
    return self.loopValues.items[index].items.len;
}

fn getLoopCounter(self: Self, index: usize) usize {
    return self.loopCounters.items[index];
}

pub fn appendLoopValue(self: *Self, index: usize, value: Value) !void {
    try self.loopValues.items[index].append(self.allocator, value);
}

pub fn getLoopValue(self: *Self, index: usize) Value {
    const val = self.loopValues.items[index].items[self.loopCounters.items[index]];
    self.loopCounters.items[index] = @rem(self.loopCounters.items[index] + 1, self.getLoopSize(index)); 
    return val;
}
