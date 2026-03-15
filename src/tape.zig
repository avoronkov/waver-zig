const std = @import("std");
const Inst = @import("./instrument.zig");
const EofError = @import("./wave.zig").EofError;
// const Wave = Inst.Wave;
const Allocator = std.mem.Allocator;

const Self = @This();

const Wave = struct {
    wave: Inst.Wave,
    node: std.DoublyLinkedList.Node,
};

allocator: Allocator,
waves: std.DoublyLinkedList,
stopping: bool = false,

pub fn init(a: Allocator) Self {
    return .{
        .allocator = a,
        .waves = .{},
    };
}

pub fn deinit(self: Self) void {
    var it = self.waves.first;
    while (it) |node| {
        it = node.next;
        self.allocator.destroy(node);
    }
}

pub fn append(self: *Self, wave: Inst.Wave) !void {
    const w = try self.allocator.create(Wave);
    w.* = .{
        .wave = wave,
        .node = .{},
    };
    // const node = try self.allocator.create(L.Node);
    // node.* = .{
    //     .data = wave,
    // };
    self.waves.append(&w.node);
}

pub fn value(self: *Self, t: f64) EofError!f64 {
    if (self.stopping and self.waves.len() == 0) {
        return error.Eof;
    }

    var it = self.waves.first;
    var val: f64 = 0;
    while (it) |node| {
        it = node.next;
        const wave: *Wave = @fieldParentPtr("node", node);
        if (wave.wave.start == null) {
            wave.wave.start = t;
        }
        const start = wave.wave.start orelse unreachable;
        if (t < start) {
            continue;
        }
        const w = wave.wave.value(t - start);
        val += w catch blk: {
            wave.wave.deinit();
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
