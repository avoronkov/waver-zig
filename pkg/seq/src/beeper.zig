const std = @import("std");
const Tape = @import("./tape.zig");
const Signaler = @import("./seq/signaler.zig");
const Context = @import("./seq/context.zig");
const Program = @import("./pelia/program.zig");
const Parser = @import("./pelia/parser.zig");

const Self = @This();

const Allocator = std.mem.Allocator;

allocator: Allocator,
io: std.Io,
clock: std.Io.Clock,
// startMicro: i64,
periodMicro: ?std.Io.Duration,
zeroBitTime: std.Io.Timestamp,
context: Context,
program: Program,
file: []const u8,
stop: ?i64,
log: ?*std.Io.Writer = null,

pub fn init(
    allocator: Allocator,
    io: std.Io,
    clock: std.Io.Clock,
    file: []const u8,
    stop: ?i64,
) !Self {
    const prog = try Parser.parseFile(allocator, io, file);
    var context = Context.init(allocator);

    try context.initSeqCounters(prog.seqCounters);
    try context.initRepeatCounters(prog.repeatCounters);
    try context.initLoopCounters(prog.loopCounters);

    return .{
        .allocator = allocator,
        .io = io,
        .clock = clock,
        // .startMicro = @truncate(clock.now(io).toMicroseconds()),
        .periodMicro = null,
        .zeroBitTime = clock.now(io),
        .context = context,
        .program = prog,
        .file = file,
        .stop = stop,
    };
}

pub fn deinit(self: *Self) void {
    self.program.deinit();
    self.context.deinit();
}

pub fn run(self: *Self, tape: *Tape) !void {
    self.context.variables = &self.program.variables;
    self.context.functions = &self.program.functions;
    self.context.user_signalers = &self.program.user_signalers;
    self.context.scaleFrequencies = self.program.scaleFrequencies;
    self.context.notes_names = self.program.notes_names;

    if (self.program.tempo) |tempo| {
        std.log.info("Tempo = {}", .{tempo});
        self.setTempo(tempo, 0);
    }

    if (self.program.stop) |stop| {
        if (self.stop == null) {
            self.stop = stop;
        }
    }

    if (self.stop) |stop| {
        std.log.info("Stop = {}", .{stop});
    }

    var bit: i64 = 0;
    var bit_time_sec: f64 = 0.05;
    while (true) {
        const bit_start = self.clock.now(self.io);
        if (self.stop) |stop| {
            if (bit >= stop) {
                std.log.info("Stopping on bit {}", .{bit});
                break;
            }
        }
        std.log.debug("Bit {}", .{bit});
        for (self.program.signalers.items) |s| {
            self.handle_signaler(s, bit, bit_time_sec, tape) catch |err| {
                std.log.err("Error: {t}", .{err});
            };
        }
        self.check_file_modified(bit) catch |err| {
            std.log.err("Error checking file update '{s}': {t}", .{ self.file, err });
        };
        bit += 1;
        if (self.periodMicro) |period| {
            const period_micro: f64 = @floatFromInt(period.toMicroseconds());
            bit_time_sec += (period_micro / 1000000);
        }
        try self.sleep(bit, bit_start);
    }
    tape.stop();
}

pub fn setTempo(self: *Self, tempo: f64, bit: i64) void {
    const periodMicro: i64 = @intFromFloat(60000000 / tempo / 4);
    self.periodMicro = std.Io.Duration.fromMicroseconds(periodMicro);
    const now = self.clock.now(self.io);
    self.zeroBitTime = now.subDuration(std.Io.Duration.fromMicroseconds(periodMicro * bit));
    // TODO do not change zeroBitTime if tempo did not change.
    std.log.info("Set tempo {}, periodMicro = {}", .{ tempo, periodMicro });
}

fn bitTime(self: *Self, bit: i64) std.Io.Timestamp {
    return self.zeroBitTime.addDuration(std.io.Duration.fromMicroseconds(self.periodMicro.toMicroseconds() * bit + 20000));
}

fn handle_signaler(self: *Self, s: Signaler, bit: i64, bit_time_sec: f64, tape: *Tape) !void {
    self.context.bit = bit;
    self.context.realBit = bit;
    self.context.duration_bits = null;
    const signals = try s.signals(&self.context);
    if (signals) |sigs| {
        defer {
            for (sigs) |sig| {
                sig.deinit(self.allocator);
            }
            self.allocator.free(sigs);
        }
        const periodFloat: f64 = @floatFromInt(if (self.periodMicro) |value| value.toMicroseconds() else 0);
        for (sigs) |sig| {
            var inst = self.program.instruments.get(sig.instrument) orelse {
                std.log.err("Instrument not found: {s}", .{sig.instrument});
                return error.NotFound;
            };
            const duration_bits = if (sig.duration_bits > 0) sig.duration_bits else if (self.context.duration_bits) |db| db else 1;
            const durFloat: f64 = @floatFromInt(duration_bits);
            const durSec: f64 = durFloat * periodFloat / 1000000;
            const w = try inst.wave(.{
                .freq = sig.freq,
                .amp = sig.amplitude,
                .dur = durSec,
            }, bit_time_sec);
            if (self.log) |log| {
                try log.print("[{d}] '{s}' \"{s}\" freq={}, amp={}, bits={}\n", .{ bit, sig.instrument, sig.note, sig.freq, sig.amplitude, duration_bits });
                try log.flush();
            }
            try tape.append(w);
        }
    }
}

fn sleep(self: Self, bit: i64, bit_start: std.Io.Timestamp) !void {
    if (self.periodMicro) |periodMicro| {
        const finish = bit_start.addDuration(periodMicro);
        const dur_ns = self.clock.now(self.io).durationTo(finish);
        std.log.debug("sleep frame [{}]: {} nano", .{ bit, dur_ns.toNanoseconds() });
        try self.io.sleep(dur_ns, .awake);
    }
}

fn check_file_modified(self: *Self, bit: i64) !void {
    if (self.program.mtime) |prog_mtime| {
        const stat = try std.Io.Dir.cwd().statFile(self.io, self.file, .{});
        if (stat.mtime.toNanoseconds() <= prog_mtime.toNanoseconds()) {
            return;
        }
        const prog = try Parser.parseFile(self.allocator, self.io, self.file);

        try self.context.initSeqCounters(prog.seqCounters);
        try self.context.initRepeatCounters(prog.repeatCounters);
        try self.context.initLoopCounters(prog.loopCounters);

        self.program.deinit();
        self.program = prog;

        self.context.variables = &self.program.variables;
        self.context.functions = &self.program.functions;
        self.context.scaleFrequencies = self.program.scaleFrequencies;
        if (self.program.tempo) |tempo| {
            std.log.info("Tempo = {}", .{tempo});
            self.setTempo(tempo, bit);
        }
        if (self.program.stop) |stop| {
            self.stop = stop;
        }
    }
}
