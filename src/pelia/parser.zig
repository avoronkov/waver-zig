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
const lisp = @import("../seq/lisp.zig");
const edo12 = @import("../scales/edo12.zig");
const literal = @import("../seq/literal.zig");
const wave_input = @import("../wave_input.zig");
const sample = @import("../sample.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const Literal = literal.Literal;

const Variables = std.StringHashMapUnmanaged(Literal);

const Self = @This();

const StatementType = enum { pragma, assignment, regular };

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
lexer: Lexer,
mtime: i128,
definedVars: std.BufSet,
definedFuncs: std.BufSet,
seqCounters: i64 = 0,

pub fn parseFile(a: Allocator, file: []const u8) !Program {
    const start = std.time.nanoTimestamp();
    var parser = try init(a, file);
    defer parser.deinit();
    const result = try parser.parse();
    const end = std.time.nanoTimestamp();
    std.debug.print("parse_file took {}ns\n", .{end - start});
    return result;
}

pub fn init(a: Allocator, file: []const u8) !Self {
    const stat = try std.fs.cwd().statFile(file);
    const lexer = try Lexer.init(a, file);

    return .{
        .allocator = a,
        .lexer = lexer,
        .mtime = stat.mtime,
        .definedVars = std.BufSet.init(a),
        .definedFuncs = std.BufSet.init(a),
    };
}

pub fn deinit(self: *Self) void {
    self.lexer.deinit();
    self.definedVars.deinit();
    self.definedFuncs.deinit();
}

pub fn parse(self: *Self) !Program {
    var prog = Program.init(self.allocator);
    errdefer prog.deinit();

    LOOP: while (true) {
        if (self.lexer.top()) |tok| {
            if (tok == Lexer.Token.eof) {
                break :LOOP;
            }

            switch (try self.nextStatementType()) {
                .pragma => try self.parsePragma(),
                .regular => try self.parseRegularSt(&prog),
                .assignment => try self.parseAssignment(&prog),
            }
        } else {
            break :LOOP;
        }
    }

    for (edo12.notes.keys()) |key| {
        const value = edo12.notes.get(key) orelse std.debug.panic("Edo12 key not found: {s}\n", .{key});
        try prog.variables.put(self.allocator, try self.allocator.dupe(u8, key), Literal{ .number = value });
    }

    prog.seqCounters = self.seqCounters;
    prog.scaleFrequencies = &edo12.frequencies;
    prog.mtime = self.mtime;

    return prog;
}

fn nextStatementType(self: *Self) !StatementType {
    const token = while (self.lexer.top()) |tok| {
        if (tok == .eol) {
            self.lexer.drop();
        } else {
            break tok;
        }
    } else return error.unexpectedEof;

    if (token == .percent or token == .double_percent) {
        return .pragma;
    }
    return switch (token) {
        .ident => |id| if (self.isIdentKnown(id)) .regular else .assignment,
        else => .regular,
    };
}

fn isIdentKnown(self: *const Self, ident: []const u8) bool {
    if (waveform.waveforms.has(ident)) {
        return true;
    }
    if (self.definedVars.contains(ident)) {
        return true;
    }
    if (self.definedFuncs.contains(ident)) {
        return true;
    }
    return false;
}

fn parseSignaler(
    self: *Self,
    prog: *Program,
) !Signaler {
    var s = Signaler.init(self.allocator);
    errdefer s.deinit();

    try self.parseSignalFilters(&s);

    try self.checkWaveformUsed(prog);

    const inst = try self.parseAtom();
    // const freq = try self.parseAtom();
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
                std.debug.print("Unexpected token while parsing end of signaler: {any}\n", .{tok});
                return error.unexpectedToken;
            },
        }
    } else {
        return error.unexpectedEof;
    }
}

fn parseSignalFilters(self: *Self, s: *Signaler) !void {
    while (self.lexer.top()) |tok| {
        if (findSignalFilterParser(tok)) |parser| {
            const filt = try parser(self);
            try s.signal_filters.insert(self.allocator, 0, filt);
        } else return;
    } else return error.unexpectedEof;
}

const ParseError = error{
    unexpectedToken,
    unexpectedEof,
    niy,
    tooBig,
    OutOfMemory,
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
                if (self.definedFuncs.contains(i)) {
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
                std.debug.print("Unexpected token while parsing atom: {any}\n", .{tok});
                return error.unexpectedToken;
            },
        };
    } else return error.unexpectedEof;
}

fn parseCommaSeparatedList(self: *Self, first: Literal) ParseError!Literal {
    var list = ArrayList(Literal){};
    errdefer {
        for (list.items) |item| {
            literal.freeLiteral(self.allocator, item);
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
    var list = ArrayList(Literal){};
    errdefer {
        for (list.items) |item| {
            literal.freeLiteral(self.allocator, item);
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
    _ = self;
    return error.niy;
}

fn parseRegularSt(
    self: *Self,
    prog: *Program,
) !void {
    const signaler = try self.parseSignaler(prog);
    try prog.signalers.append(self.allocator, signaler);
}

fn parseAssignment(
    self: *Self,
    prog: *Program,
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
            return self.parseFunctionAssignment(prog, name, argname);
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
                try self.parseInstrumentFilters(&inst);
                try prog.instruments.put(
                    self.allocator,
                    try prog.allocator.dupe(u8, name),
                    inst,
                );
                try self.definedVars.insert(name);
                return;
            }
        },
        .string => |filepath| {
            self.lexer.drop();
            const smp = try sample.parseSampleFile(self.allocator, filepath);
            errdefer smp.deinit();
            const wi = wave_input.WaveInput{ .sample = smp };
            var inst = Instrument.init(self.allocator, wi);
            try self.parseInstrumentFilters(&inst);
            try prog.instruments.put(
                self.allocator,
                try prog.allocator.dupe(u8, name),
                inst,
            );
            try self.definedVars.insert(name);
            return;
        },
        else => {},
    }

    // variable assignment
    const atom = try self.parseAtom();
    const key = try self.allocator.dupe(u8, name);
    try prog.variables.put(self.allocator, key, atom);
}

fn parseFunctionAssignment(self: *Self, prog: *Program, name: []const u8, argname: []const u8) !void {
    const t3 = self.lexer.pop() orelse return error.unexpectedEof;
    if (t3 != .assign) {
        return error.unexpectedToken;
    }
    const raw = try self.parseAtom();
    defer literal.freeLiteral(self.allocator, raw);
    const body = try literal.substitute(self.allocator, raw, .{ .ident = try primitives.Ident.init(argname) }, .arg);
    try prog.functions.put(prog.allocator, try prog.allocator.dupe(u8, name), body);
    try self.definedFuncs.insert(name);
}

fn parseInstrumentFilters(self: *Self, in: *Instrument) ParseError!void {
    while (self.lexer.pop()) |tok| {
        if (tok == .eol or tok == .eof) {
            return;
        }
        if (tok != .vertical_bar) {
            std.debug.print("Unexpected token while parsing instrument filters: {any}\n", .{tok});
            return error.unexpectedToken;
        }

        const code = try self.parseAtom();
        literal.dumpLiteral("Lisp code", code);
        try in.add_filter(filter.Filter{
            .code = filter.LispCode.init(self.allocator, code),
        });
    }
}

// Signal filter parsers
fn parseEvery(self: *Self) ParseError!signal_filter.SignalFilter {
    // drop ":"
    self.lexer.drop();

    if (self.lexer.pop()) |arg| {
        switch (arg) {
            .number => |n| return signal_filter.SignalFilter{ .every = signal_filter.Every{ .n = n } },
            else => return error.unexpectedToken,
        }
    } else return error.unexpectedEof;
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
    literals[1] = .{ .number = self.seqCounters };
    literals[2] = arg;

    self.seqCounters += 1;

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
