const std = @import("std");
const Tape = @import("./tape.zig");
const Signaler = @import("./seq/signaler.zig");
const Context = @import("./seq/context.zig");
const Program = @import("./pelia/program.zig");
const Parser = @import("./pelia/parser.zig");

const Self = @This();

const Allocator = std.mem.Allocator;

allocator: Allocator,
tape: *Tape,
startMicro: i64,
periodMicro: i64,
periodFloat: f64,
context: Context,
program: Program,
file: []const u8,

pub fn init(
    allocator: Allocator,
    file: []const u8,
    tape: *Tape,
    periodMicro: i64,
) !Self {
    const prog = try Parser.parseFile(allocator, file);
    var context = Context.init(allocator);

    const sc: usize = @intCast(prog.seqCounters);
    try context.initSeqCounters(sc);

    return .{
        .allocator = allocator,
        .tape = tape,
        .startMicro = std.time.microTimestamp(),
        .periodMicro = periodMicro,
        .periodFloat = @floatFromInt(periodMicro),
        .context = context,
        .program = prog,
        .file = file,
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
    while (bit < 16) {
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
        self.sleep(bit);
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
            try self.tape.append(w);
        }
    }
}

fn sleep(self: Self, frame: i64) void {
    const dur_ns: u64 = @intCast(1000 * (self.startMicro + (frame * self.periodMicro) - std.time.microTimestamp()));
    std.log.debug("sleep frame [{}]: {} nano", .{frame, dur_ns});
    std.Thread.sleep(dur_ns);
}

fn check_file_modified(self: *Self) !void {
    const stat = try std.fs.cwd().statFile(self.file);
    if (stat.mtime <= self.program.mtime) {
        return;
    }
    const prog = try Parser.parseFile(self.allocator, self.file);

    const sc: usize = @intCast(prog.seqCounters);
    try self.context.initSeqCounters(sc);

    self.program.deinit();
    self.program = prog;

    self.context.variables = &self.program.variables;
    self.context.functions = &self.program.functions;
    self.context.scaleFrequencies = self.program.scaleFrequencies;
}
