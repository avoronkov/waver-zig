const std = @import("std");
const waveform = @import("./waveform.zig");
const wave_input = @import("./wave_input.zig");
const filter = @import("./filter.zig");
const Note = @import("./note.zig");
const Chain = @import("./chain.zig");
const EofError = @import("./wave.zig").EofError;

const Self = @This();

const Allocator = std.mem.Allocator;
const Filters = std.ArrayListUnmanaged(filter.Filter);

const WaveInput = wave_input.WaveInput;

allocator: Allocator,
wf: WaveInput,
filters: Filters,

pub fn init(a: Allocator, w: WaveInput) Self {
    return .{
        .allocator = a,
        .wf = w,
        .filters = Filters{},
    };
}

pub fn deinit(self: *Self) void {
    for (self.filters.items) |*f| {
        filter.free_filter(f);
    }
    self.filters.deinit(self.allocator);

    // Deinit samples
    switch (self.wf) {
        .sample => |s| s.deinit(),
        else => {},
    }
}

pub fn copy(self: *const Self) !Self {
    var filters = Filters{};
    for (self.filters.items) |fl| {
        const new_fl = try filter.copy_filter(self.allocator, fl);
        try filters.append(self.allocator, new_fl);
    }
    return .{
        .allocator = self.allocator,
        .wf = try wave_input.copy(&self.wf),
        .filters = filters,
    };
}

pub fn add_filter(self: *Self, f: filter.Filter) !void {
    try self.filters.append(self.allocator, f);
}

pub fn value(self: Self, t: f64, note: Note) EofError!f64 {
   const n: i32 = @intCast(self.filters.items.len); 
   return self.value_of(n - 1, t, note);
}

pub fn value_of(self: *const Self, n: i32, t: f64, note: Note) EofError!f64 {
    if (n == -1) {
        return wave_input.value(&self.wf, t, note);
    }

    // TODO get rid of cyclic init
    const c = Chain.init(self);
    const i: usize = @intCast(n);
    return filter.filter_apply(self.filters.items[i], c, n, t, note);
}

pub fn wave(self: Self, note: Note, start: ?f64) !Wave {
    const inst = try self.copy();
    return Wave{
        .start = start,
        .note = note,
        .inst = inst,
    };
}

pub const Wave = struct {
    // Start time in seconds.
    start: ?f64,
    note: Note,
    inst: Self,

    pub fn value(self: Wave, t: f64) EofError!f64 {
        return self.inst.value(t, self.note);
    }

    pub fn deinit(self: *Wave) void {
        self.inst.deinit();
    }
};
