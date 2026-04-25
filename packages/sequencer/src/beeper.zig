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
startMicro: i64,
periodMicro: ?i64,
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

    const sc: usize = @intCast(prog.seqCounters);
    try context.initSeqCounters(sc);

    return .{
        .allocator = allocator,
        .io = io,
        .clock = clock,
        .startMicro = @truncate(clock.now(io).toMicroseconds()),
        .periodMicro = null,
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
    self.context.scaleFrequencies = self.program.scaleFrequencies;
    var bit: i64 = 0;
    while (true) {
        if (self.stop) |stop| {
            if (bit >= stop) {
                std.log.info("Stopping on bit {}", .{bit});
                break;
            }
        }
        std.log.info("Bit {}", .{bit});
        for (self.program.signalers.items) |s| {
             self.handle_signaler(s, bit, tape) catch |err| {
                 std.log.err("Error: {t}", .{ err });
             };
        }
        bit += 1;
        self.check_file_modified() catch |err| {
             std.log.err("Error checking file update: {t}", .{ err });
        };
        try self.sleep(bit);
    }
    tape.stop();
}

pub fn setTempo(self: *Self, tempo: f64) void {
    const periodMicro: i64 = @intFromFloat(60000000 / tempo / 4);
    self.periodMicro = periodMicro;
    std.log.debug("Set tempo {}, periodMicro = {}", .{tempo, periodMicro});
}

fn handle_signaler(self: *Self, s: Signaler, bit: i64, tape: *Tape) !void {
    self.context.bit = bit;
    self.context.realBit = bit;
    const signals = try s.signals(&self.context);
    if (signals) |sigs| {
        defer self.allocator.free(sigs);
        const periodFloat: f64 = @floatFromInt(if (self.periodMicro) |value| value else 0);
        for (sigs) |sig| {
            var inst = self.program.instruments.get(sig.instrument.string()) orelse {
                std.log.err("Instrument not found: {s}", .{sig.instrument.string()});
                return error.NotFound;
            };
            const durFloat: f64 = @floatFromInt(sig.duration_bits);
            const durSec: f64 = durFloat * periodFloat / 1000000;
            const w = try inst.wave(.{
                .freq = sig.freq,
                .amp = sig.amplitude,
                .dur = durSec,
            }, null);
            if (self.log) |log| {
                try log.print("[{d}] '{s}' freq={}, amp={}, bits={}\n", .{bit, sig.instrument.string(), sig.freq, sig.amplitude, sig.duration_bits});
                try log.flush();
            }
            try tape.append(w);
        }
    }
}

fn sleep(self: Self, frame: i64) !void {
    if (self.periodMicro) |periodMicro| {
        const dur_ns: i96 = @intCast(1000 * (self.startMicro + (frame * periodMicro) - self.clock.now(self.io).toMicroseconds()));
        std.log.debug("sleep frame [{}]: {} nano", .{frame, dur_ns});
        try self.io.sleep(.fromNanoseconds(dur_ns), .awake);
    }
}

fn check_file_modified(self: *Self) !void {
    const stat = try std.Io.Dir.cwd().statFile(self.io, self.file, .{});
    if (stat.mtime.toNanoseconds() <= self.program.mtime) {
        return;
    }
    const prog = try Parser.parseFile(self.allocator, self.io, self.file);

    const sc: usize = @intCast(prog.seqCounters);
    try self.context.initSeqCounters(sc);

    self.program.deinit();
    self.program = prog;

    self.context.variables = &self.program.variables;
    self.context.functions = &self.program.functions;
    self.context.scaleFrequencies = self.program.scaleFrequencies;
}
