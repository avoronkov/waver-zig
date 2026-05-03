const std = @import("std");
const Lexer = @import("./lexer.zig");
const Program = @import("./program.zig");
const Signaler = @import("../seq/signaler.zig");
const signal_func = @import("../seq/signal_func.zig");
const signal_filter = @import("../seq/signal_filter.zig");
const Instrument = @import("../instrument.zig");
const filter = @import("../filter.zig");
const primitives = @import("./primitives.zig");
const waveform = @import("../waveform.zig");
const edo12 = @import("../scales/edo12.zig");
const literal = @import("../seq/literal.zig");
const wave_input = @import("../wave_input.zig");
const sample = @import("../sample.zig");
const setStructField = @import("../utils/struct.zig").setStructField;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Literal = literal.Literal;

const Self = @This();

const StatementType = enum { pragma, assignment, regular, eof };

const SignalFilterParser = *const fn (self: *Self) ParseError!signal_filter.SignalFilter;

const signalFilterParsers = [_]struct {
    token: Lexer.Token,
    parse: SignalFilterParser,
}{
    .{
        .token = .colon,
        .parse = parseEvery,
    },
    .{
        .token = .plus,
        .parse = parseBitShift,
    },
};

const FuncParser = *const fn (self: *Self) ParseError!Literal;

const funcParsers = [_]struct {
    token: Lexer.Token,
    parse: FuncParser,
}{
    .{ .token = .ampersand, .parse = parseRand },
    .{
        .token = Lexer.Token{ .ident = "rand" },
        .parse = parseRand,
    },
    .{ .token = .at, .parse = parseSeq },
    .{
        .token = Lexer.Token{ .ident = "seq" },
        .parse = parseSeq,
    },
};

const atoms = [_]struct {
    token: Lexer.Token,
    atom: Literal,
}{
    .{
        .token = Lexer.Token{ .ident = "sin" },
        .atom = .sin,
    },
    .{
        .token = Lexer.Token{ .ident = "pow" },
        .atom = .pow,
    },
};

allocator: Allocator,
io: std.Io,
lexer: Lexer,
mtime: ?std.Io.Timestamp,
prog: *Program,

pub fn parseFile(a: Allocator, io: std.Io, filename: []const u8) !Program {
    const clock = std.Io.Clock.real;
    const start = clock.now(io);

    const stat = try std.Io.Dir.cwd().statFile(io, filename, .{});

    const file = try std.Io.Dir.cwd().openFile(io, filename, .{});
    var file_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &file_buffer);

    var prog = Program.init(a);
    errdefer prog.deinit();

    var parser = try init(a, io, &file_reader.interface, &prog, stat.mtime);
    defer parser.deinit();

    try parser.parse();

    const dur = start.untilNow(io, clock);
    std.log.info("parse_file took {}ms\n", .{dur.toMicroseconds()});

    return prog;
}

pub fn init(a: Allocator, io: std.Io, reader: *std.Io.Reader, prog: *Program, mtime: ?std.Io.Timestamp) !Self {
    const lexer = try Lexer.init(a, reader);

    return .{
        .allocator = a,
        .io = io,
        .lexer = lexer,
        .mtime = mtime,
        .prog = prog,
    };
}

pub fn deinit(self: *Self) void {
    self.lexer.deinit();
}

fn parseInner(self: *Self) !void {
    LOOP: while (true) {
        if (self.lexer.top()) |tok| {
            if (tok == Lexer.Token.eof) {
                break :LOOP;
            }

            switch (try self.nextStatementType()) {
                .pragma => try self.parsePragma(),
                .regular => try self.parseRegularSt(),
                .assignment => try self.parseAssignment(),
                .eof => break :LOOP,
            }
        } else {
            break :LOOP;
        }
    }
}

pub fn parse(self: *Self) !void {
    for (edo12.notes.keys()) |key| {
        const value = edo12.notes.get(key) orelse std.debug.panic("Edo12 key not found: {s}\n", .{key});
        try self.prog.variables.put(self.allocator, try self.allocator.dupe(u8, key), Literal{ .number = value });
    }

    // Parse edo12 scale functions
    var reader = std.Io.Reader.fixed(edo12.code);
    var parser = try init(self.allocator, self.io, &reader, self.prog, null);
    defer parser.deinit();
    try parser.parseInner();

    // Parse the program itself
    try self.parseInner();

    // prog.seqCounters = self.seqCounters;
    self.prog.scaleFrequencies = &edo12.frequencies;
    self.prog.mtime = self.mtime;
}

fn nextStatementType(self: *Self) !StatementType {
    const token = while (self.lexer.top()) |tok| {
        if (tok == .eol) {
            self.lexer.drop();
        } else {
            break tok;
        }
    } else return error.unexpectedEof;

    if (token == .eof) {
        return .eof;
    }

    if (token == .percent or token == .double_percent) {
        return .pragma;
    }
    return switch (token) {
        .ident => |id| if (self.isIdentKnown(id)) .regular else .assignment,
        else => .regular,
    };
}

/// Used to check if first token in a line is known to detect type of statement.
fn isIdentKnown(self: *const Self, ident: []const u8) bool {
    if (waveform.waveforms.has(ident)) {
        return true;
    }
    if (self.prog.instruments.contains(ident)) {
        return true;
    }
    if (self.prog.functions.contains(ident)) {
        return true;
    }
    if (self.prog.user_signalers.contains(ident)) {
        return true;
    }
    return false;
}

fn parseSignaler(
    self: *Self,
) !Signaler {
    var s = Signaler.init(self.allocator);
    errdefer s.deinit();

    try self.parseSignalFilters(&s);

    try self.checkWaveformUsed(self.prog);

    if (self.lexer.top()) |tk| {
        switch (tk) {
            .ident => |id| {
                if (self.prog.user_signalers.contains(id)) {
                    self.lexer.drop();
                    try s.add_signaler(id);
                    // TODO copypaste
                    if (self.lexer.pop()) |tok| {
                        switch (tok) {
                            .eol => return s,
                            .eof => return s,
                            else => return {
                                std.log.err("Unexpected token while parsing end of signaler: {any}\n", .{tok});
                                return error.unexpectedToken;
                            },
                        }
                    } else {
                        return error.unexpectedEof;
                    }
                }
            },
            else => {},
        }
    }

    const inst = try self.parseAtom();
    const freq: Literal = if (self.lexer.top()) |tok| blk: {
        break :blk if (tok == .eol or tok == .eof)
            Literal{ .float = 0 }
        else
            try self.parseAtom();
    } else Literal{ .float = 0 };

    try s.add_func(signal_func.SignalFunc{
        .inst = inst,
        .freq = freq,
        .amplitude = Literal{ .float = 0.75 },
        .duration_bits = Literal{ .number = 1 },
    });

    if (self.lexer.pop()) |tok| {
        switch (tok) {
            .eol => return s,
            .eof => return s,
            else => return {
                std.log.err("Unexpected token while parsing end of signaler: {any}\n", .{tok});
                return error.unexpectedToken;
            },
        }
    } else {
        return error.unexpectedEof;
    }
}

fn parseRangeStatement(self: *Self, s: *Signaler, start: i64) !void {
    self.lexer.drop();
    if (self.lexer.pop()) |token| {
        if (token != .double_dot) {
            std.log.err("Unexpected token while parsing range statement: {any}\n", .{token});
            return error.unexpectedToken;
        }
    } else return error.unexpectedEof;
    try s.signal_filters.append(self.allocator, signal_filter.SignalFilter{
        .moreOrEqual = signal_filter.MoreOrEqual{ .n = start },
    });
    if (self.lexer.top()) |token| {
        switch (token) {
            .number => |n| {
                self.lexer.drop();
                try s.signal_filters.append(self.allocator, signal_filter.SignalFilter{
                    .lessThan = signal_filter.LessThan{ .n = n },
                });
            },
            else => return,
        }
    } else return error.unexpectedEof;
}

fn parseSignalFilters(self: *Self, s: *Signaler) !void {
    while (self.lexer.top()) |tok| {
        if (findSignalFilterParser(tok)) |parser| {
            const filt = try parser(self);
            try s.signal_filters.insert(self.allocator, 0, filt);
        } else switch (tok) {
            .number => |start| {
                try self.parseRangeStatement(s, start);
            },
            else => return,
        }
    } else return error.unexpectedEof;
}

const ParseError = error{
    unexpectedToken,
    unexpectedEof,
    niy,
    tooBig,
    OutOfMemory,
    badKey,
    valueTypeMismatch,
};

fn parseAtom(self: *Self) ParseError!Literal {
    const first = try self.parseSingleAtom();
    if (self.lexer.top()) |tok| {
        if (tokensEql(tok, .comma)) {
            self.lexer.drop();
            return self.parseCommaSeparatedList(first);
        }
    }
    return first;
}

fn parseSingleAtom(self: *Self) ParseError!Literal {
    if (self.lexer.pop()) |tok| {
        if (findFuncParser(tok)) |p| {
            return p(self);
        }
        if (findAtom(tok)) |at| {
            return at;
        }
        return switch (tok) {
            .ident => |i| blk: {
                if (self.prog.functions.contains(i)) {
                    const arg = try self.parseAtom();
                    var list = try self.allocator.alloc(Literal, 3);
                    errdefer self.allocator.free(list);
                    list[0] = .func;
                    list[1] = .{ .ident = try primitives.Ident.init(i) };
                    list[2] = arg;
                    return .{ .list = list };
                }
                break :blk Literal{ .ident = try primitives.Ident.init(i) };
            },
            .float => |f| Literal{ .float = f },
            .number => |n| Literal{ .number = n },
            .left_square_bracket => try self.parseBracketsList(),
            .plus => .plus,
            .multiply => .multiply,
            .minus => blk: {
                if (self.lexer.pop()) |t2| {
                    switch (t2) {
                        .float => |f| break :blk Literal{ .float = -f },
                        .number => |n| break :blk Literal{ .number = -n },
                        else => return error.unexpectedToken,
                    }
                } else return error.unexpectedEof;
            },
            else => {
                std.log.err("Unexpected token while parsing atom: {any} ({})\n", .{tok, self.lexer.current});
                return error.unexpectedToken;
            },
        };
    } else return error.unexpectedEof;
}

fn parseCommaSeparatedList(self: *Self, first: Literal) ParseError!Literal {
    var list: ArrayList(Literal) = .empty;
    errdefer {
        for (list.items) |item| {
            item.deinit(self.allocator);
        }
        list.deinit(self.allocator);
    }

    try list.append(self.allocator, first);
    while (true) {
        const item = try self.parseSingleAtom();
        try list.append(self.allocator, item);

        if (self.lexer.top()) |t| {
            if (t != .comma) {
                break;
            } else {
                self.lexer.drop();
            }
        } else {
            break;
        }
    } else return error.unexpectedEof;
    return .{ .list = try list.toOwnedSlice(self.allocator) };
}

fn parseBracketsList(self: *Self) ParseError!Literal {
    var list: ArrayList(Literal) = .empty;
    errdefer {
        for (list.items) |item| {
            item.deinit(self.allocator);
        }
        list.deinit(self.allocator);
    }

    while (true) {
        if (self.lexer.top()) |t| {
            if (t == .right_square_bracket) {
                self.lexer.drop();
                break;
            }
        } else {
            return error.unexpectedEof;
        }
        const atom = try self.parseAtom();
        try list.append(self.allocator, atom);
    }

    return Literal{
        .list = try list.toOwnedSlice(self.allocator),
    };
}

// Check if waveform name is used directly and insert.
fn checkWaveformUsed(self: *Self, prog: *Program) !void {
    if (self.lexer.top()) |t| {
        switch (t) {
            .ident => |id| {
                if (waveform.waveforms.get(id)) |wf| {
                    const wi = wave_input.WaveInput{ .waveform = wf };
                    const inst = Instrument.init(self.allocator, wi);
                    if (prog.instruments.get(id)) |_| {
                        // Instrument already exists.
                        return;
                    }
                    try prog.instruments.put(
                        prog.allocator,
                        try prog.allocator.dupe(u8, id),
                        inst,
                    );
                    return;
                }
            },
            else => return,
        }
    }
}

fn parsePragma(self: *Self) !void {
    // Drop % (%% not supported)
    self.lexer.drop();
    const pragma = if (self.lexer.pop()) |tok| blk: {
        break :blk switch (tok) {
            .ident => |id| id,
            else => return error.unexpectedToken,
        };
    } else return error.unexpectedEof;

    if (std.mem.eql(u8, pragma, "tempo")) {
        const tempo: f64 = if (self.lexer.pop()) |tok| blk: {
            break :blk switch (tok) {
                .float => |f| f,
                .number => |n| @floatFromInt(n),
                else => return error.unexpectedToken,
            };
        } else return error.unexpectedEof;
        self.prog.tempo = tempo;
    }
    else if (std.mem.eql(u8, pragma, "stop")) {
        const stop: i64 = if (self.lexer.pop()) |tok| blk: {
            break :blk switch (tok) {
                .number => |n| n,
                else => return error.unexpectedToken,
            };
        } else return error.unexpectedEof;
        self.prog.stop = stop;
    }
    else if (std.mem.eql(u8, pragma, "scale")) {
        const scale_name: []const u8 = if (self.lexer.pop()) |tok| blk: {
            break :blk switch (tok) {
                .ident => |s| s,
                else => return error.unexpectedToken,
            };
        } else return error.unexpectedEof;
        if (!std.mem.eql(u8, scale_name, "edo12")) {
            std.log.err("Unknown scale: {s}", .{scale_name});
            return error.unknownScale;
        }
        // TODO: proper edo12 and edo19 support
    } else {
        std.log.err("Unknown pragma: {s}", .{pragma});
        return error.unknownPragma;
    }

    if (self.lexer.pop()) |tok| {
        if (tok != .eol and tok != .eof) {
            return error.unexpectedToken;
        }
    }
}

fn parseRegularSt(
    self: *Self,
) !void {
    const signaler = try self.parseSignaler();
    try self.prog.signalers.append(self.allocator, signaler);
}

// var = <value>
// func arg = <body>
// sig == <signals>
fn parseAssignment(
    self: *Self,
) !void {
    const name = if (self.lexer.pop()) |tok| blk: {
        break :blk switch (tok) {
            .ident => |id| id,
            else => return error.unexpectedToken,
        };
    } else return error.unexpectedEof;

    const t2 = self.lexer.pop() orelse return error.unexpectedEof;
    switch (t2) {
        .ident => |argname| {
            return self.parseFunctionAssignment(name, argname);
        },
        .double_assign => {
            return self.parseSignalerAssignment(name);
        },
        else => {},
    }
    if (t2 != .assign) {
        return error.unexpectedToken;
    }

    const t3 = self.lexer.top() orelse return error.unexpectedEof;
    switch (t3) {
        .ident => |id| {
            if (waveform.waveforms.get(id)) |wf| {
                // Instrument assignment
                self.lexer.drop();
                const wi = wave_input.WaveInput{ .waveform = wf };
                var inst = Instrument.init(self.allocator, wi);
                errdefer inst.deinit();
                try self.parseInstrumentFilters(&inst);
                try self.prog.instruments.put(
                    self.prog.allocator,
                    try self.prog.allocator.dupe(u8, name),
                    inst,
                );
                return;
            }
        },
        .string => |filepath| {
            self.lexer.drop();
            const smp = try sample.parseSampleFile(self.allocator, self.io, filepath);
            errdefer smp.deinit();
            const wi = wave_input.WaveInput{ .sample = smp };
            var inst = Instrument.init(self.allocator, wi);
            errdefer inst.deinit();
            try self.parseInstrumentFilters(&inst);
            try self.prog.instruments.put(
                self.prog.allocator,
                try self.prog.allocator.dupe(u8, name),
                inst,
            );
            return;
        },
        else => {},
    }

    // variable assignment
    const atom = try self.parseAtom();
    const key = try self.allocator.dupe(u8, name);
    try self.prog.variables.put(self.allocator, key, atom);
}

// func arg = <body>
fn parseFunctionAssignment(self: *Self, name: []const u8, argname: []const u8) !void {
    const t3 = self.lexer.pop() orelse return error.unexpectedEof;
    if (t3 != .assign) {
        return error.unexpectedToken;
    }
    const raw = try self.parseAtom();
    defer raw.deinit(self.allocator);
    const body = try literal.substitute(self.allocator, raw, .{ .ident = try primitives.Ident.init(argname) }, .arg);
    try self.prog.functions.put(self.prog.allocator, try self.prog.allocator.dupe(u8, name), body);
}

// sig = <signaler>
fn parseSignalerAssignment(self: *Self, name: []const u8) !void {
    const signaler = try self.parseSignaler();
    try self.prog.user_signalers.put(self.prog.allocator, try self.prog.allocator.dupe(u8, name), signaler);
}

fn parseInstrumentFilters(self: *Self, in: *Instrument) ParseError!void {
    while (self.lexer.pop()) |tok| {
        if (tok == .eol or tok == .eof) {
            return;
        }
        if (tok != .vertical_bar) {
            std.log.err("Unexpected token while parsing instrument filters: {any}\n", .{tok});
            return error.unexpectedToken;
        }

        const tfilt = self.lexer.top() orelse return error.unexpectedEof;
        switch (tfilt) {
            .ident => |id| {
                if (filter.filters.get(id)) |fl| {
                    self.lexer.drop();
                    std.log.info("Add filter {s}\n", .{id});
                    var flt = fl;
                    try self.parseInstrumentFilterParams(&flt);
                    try in.add_filter(flt);
                } else {
                    std.log.err("Unknown filter: {s}\n", .{id});
                    return error.unexpectedToken;
                }
            },
            else => {
                const code = try self.parseAtom();
                literal.dumpLiteral("Lisp code", code);
                try in.add_filter(filter.Filter{
                    .code = filter.LispCode.init(self.allocator, code),
                });
            },
        }
    }
}

fn parseInstrumentFilterParams(self: *Self, flt: *filter.Filter) !void {
    while (self.lexer.top()) |tok| {
        if (tok == .eol or tok == .eof or tok == .vertical_bar) {
            return;
        }
        self.lexer.drop();

        // Parse param name.
        const name = switch (tok) {
            .ident => |id| id,
            else => {
                std.log.err("parseInstrumentFilterParams: unexpected token {any}\n", .{tok});
                return error.unexpectedToken;
            },
        };

        // Skip .assign.
        const assignTok = self.lexer.pop() orelse return error.unexpectedEof;
        if (assignTok != .assign) {
            std.log.err("parseInstrumentFilterParams: unexpected token {any}\n", .{assignTok});
            return error.unexpectedToken;
        }

        // Parse param value: [-](int | float).
        const value1 = self.lexer.pop() orelse return error.unexpectedEof;
        try switch (value1) {
            .number => |n| setFilterParam(flt, name, n),
            .float => |f| setFilterParam(flt, name, f),
            .ident => |i| 
                if (std.mem.eql(u8, i, "true"))
                    setFilterParam(flt, name, true)
                else if (std.mem.eql(u8, i, "true"))
                    setFilterParam(flt, name, false)
                else {
                    std.log.err("Unexpected identifier: {s}", .{i});
                    return error.unexpectedToken;
                },
            // TODO handle [-] (negative values).
            else => {
                std.log.err("Unexpected token: {any}", .{value1});
                return error.unexpectedToken;
            },
        };
    }
}

fn setFilterParam(flt: *filter.Filter, key: []const u8, value: anytype) !void {
    try switch (flt.*) {
        .am => |*v| setStructField(v, key, value),
        .exp => |*v| setStructField(v, key, value),
        .pan => |*v| setStructField(v, key, value),
        .flanger => |*v| setStructField(v, key, value),
        .adsr => |*v| setStructField(v, key, value),
        .code => {},
    };
}

// Signal filter parsers
fn parseEvery(self: *Self) ParseError!signal_filter.SignalFilter {
    // drop ":"
    self.lexer.drop();

    const lit = try self.parseAtom();
    defer lit.deinit(self.allocator);
    switch (lit) {
        .number => |n| return signal_filter.SignalFilter{ .every = signal_filter.Every{ .n = n } },
        .list => |lst| {
            var res = try self.allocator.alloc(i64, lst.len);
            errdefer self.allocator.free(res);
            for (lst, 0..) |it, i| {
                switch (it) {
                    .number => |n| {
                        res[i] = n;
                    },
                    else => {
                        std.log.err("Bad argument for everyList(:) function: {any}", .{it});
                        return error.unexpectedToken;
                    }
                }
            }
            return signal_filter.SignalFilter{
                .everyList = signal_filter.EveryList{ .allocator = self.allocator, .args = res },
            };
        },
        else => {
            std.log.err("Bad argument for every(:) function: {any}", .{lit});
            return error.unexpectedToken;
        },
    }
}

fn parseBitShift(self: *Self) ParseError!signal_filter.SignalFilter {
    // drop "+"
    self.lexer.drop();

    if (self.lexer.pop()) |arg| {
        switch (arg) {
            .number => |n| return signal_filter.SignalFilter{ .bitShift = signal_filter.BitShift{ .n = n } },
            else => return error.unexpectedToken,
        }
    } else return error.unexpectedEof;
}

// Function parsers
fn parseRand(self: *Self) ParseError!Literal {
    const arg = try self.parseAtom();
    var literals = try self.allocator.alloc(Literal, 2);
    literals[0] = .rand;
    literals[1] = arg;
    return Literal{
        .list = literals,
    };
}

fn parseSeq(self: *Self) ParseError!Literal {
    const arg = try self.parseAtom();

    var literals = try self.allocator.alloc(Literal, 3);
    literals[0] = .seq;
    literals[1] = .{ .number = self.prog.seqCounters };
    literals[2] = arg;

    self.prog.seqCounters += 1;

    return Literal{
        .list = literals,
    };
}

fn findSignalFilterParser(tok: Lexer.Token) ?SignalFilterParser {
    for (signalFilterParsers) |item| {
        if (tokensEql(item.token, tok)) {
            return item.parse;
        }
    }
    return null;
}

fn findFuncParser(tok: Lexer.Token) ?FuncParser {
    for (funcParsers) |item| {
        if (tokensEql(item.token, tok)) {
            return item.parse;
        }
    }
    return null;
}

fn findAtom(tok: Lexer.Token) ?Literal {
    for (atoms) |at| {
        if (tokensEql(at.token, tok)) {
            return at.atom;
        }
    }
    return null;
}

fn tokensEql(a: Lexer.Token, b: Lexer.Token) bool {
    return (std.meta.activeTag(a) == std.meta.activeTag(b)) and switch (a) {
        .ident => |tokId| std.mem.eql(u8, tokId, b.ident),
        .string => |s| std.mem.eql(u8, s, b.string),
        else => true,
    };
}

test "pragma tempo" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const input =
        \\% tempo 144
        \\
    ;
    var reader = std.Io.Reader.fixed(input);
    var prog = Program.init(allocator);
    defer prog.deinit();

    var parser = try init(allocator, io, &reader, &prog, null);
    defer parser.deinit();

    try parser.parse();

    try std.testing.expectEqual(prog.tempo, 144);
}

test "pragma stop" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const input =
        \\% stop 82
        \\
    ;
    var reader = std.Io.Reader.fixed(input);
    var prog = Program.init(allocator);
    defer prog.deinit();

    var parser = try init(allocator, io, &reader, &prog, null);
    defer parser.deinit();

    try parser.parse();

    try std.testing.expectEqual(prog.stop, 82);
}
