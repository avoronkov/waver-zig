const std = @import("std");
const Inst = @import("./instrument.zig");
const EofError = @import("./wave.zig").EofError;
const Wave = Inst.Wave;
const Allocator = std.mem.Allocator;

const Self = @This();

const L = std.DoublyLinkedList(Wave);

allocator: Allocator,
waves: L,
stopping: bool = false,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .waves = L{},
    };
}

pub fn deinit(self: Self) void {
    var it = self.waves.first;
    while (it) |node| {
        it = node.next;
        self.allocator.destroy(node);
    }
}

pub fn append(self: *Self, wave: Wave) !void {
    const node = try self.allocator.create(L.Node);
    node.* = .{
        .data = wave,
    };
    self.waves.append(node);
}

pub fn value(self: *Self, t: f64) EofError!f64 {
    if (self.stopping and self.waves.len == 0) {
        return error.Eof;
    }

    var it = self.waves.first;
    var val: f64 = 0;
    while (it) |node| {
        it = node.next;
        if (node.data.start == null) {
            node.data.start = t;
        }
        const start = node.data.start orelse unreachable;
        if (t < start) {
            continue;
        }
        const w = node.data.value(t - start);
        val += w catch blk: {
            node.data.deinit();
            self.waves.remove(node);
            self.allocator.destroy(node);
            break :blk 0;
        };
    }
    return val;
}

pub fn stop(self: *Self) void {
    self.stopping = true;
}
