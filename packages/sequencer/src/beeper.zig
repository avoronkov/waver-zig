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
tape: *Tape,
startMicro: i64,
periodMicro: i64,
periodFloat: f64,
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
    tape: *Tape,
    periodMicro: i64,
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
        .tape = tape,
        .startMicro = @truncate(clock.now(io).toMicroseconds()),
        .periodMicro = periodMicro,
        .periodFloat = @floatFromInt(periodMicro),
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

pub fn run(self: *Self) !void {
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
             self.handle_signaler(s, bit) catch |err| {
                 std.log.err("Error: {t}", .{ err });
             };
        }
        bit += 1;
        self.check_file_modified() catch |err| {
             std.log.err("Error checking file update: {t}", .{ err });
        };
        try self.sleep(bit);
    }
    self.tape.stop();
}

fn handle_signaler(self: *Self, s: Signaler, bit: i64) !void {
    self.context.bit = bit;
    self.context.realBit = bit;
    const signals = try s.signals(&self.context);
    if (signals) |sigs| {
        defer self.allocator.free(sigs);
        for (sigs) |sig| {
            var inst = self.program.instruments.get(sig.instrument.string()) orelse {
                std.log.err("Instrument not found: {s}", .{sig.instrument.string()});
                return error.NotFound;
            };
            const durFloat: f64 = @floatFromInt(sig.duration_bits);
            const w = try inst.wave(.{
                .freq = sig.freq,
                .amp = sig.amplitude,
                .dur = durFloat * self.periodFloat / 1000000,
            }, null);
            if (self.log) |log| {
                try log.print("[{d}] '{s}' freq={}, amp={}, dur={}\n", .{bit, sig.instrument.string(), sig.freq, sig.amplitude, (durFloat * self.periodFloat / 1000000)});
                try log.flush();
            }
            try self.tape.append(w);
        }
    }
}

fn sleep(self: Self, frame: i64) !void {
    const dur_ns: i96 = @intCast(1000 * (self.startMicro + (frame * self.periodMicro) - self.clock.now(self.io).toMicroseconds()));
    std.log.debug("sleep frame [{}]: {} nano", .{frame, dur_ns});
    try self.io.sleep(.fromNanoseconds(dur_ns), .awake);
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
