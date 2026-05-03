const std = @import("std");
const parse_utils = @import("./parse_utils.zig");

const Allocator = std.mem.Allocator;

const Self = @This();

pub const Token = union(enum) {
    colon,
    plus,
    minus,
    multiply,
    less,
    more,
    arrow_right,
    comma,
    assign,
    double_assign,
    ampersand,
    at,
    left_curly_bracket,
    right_curly_bracket,
    left_square_bracket,
    right_square_bracket,
    vertical_bar,
    double_dot,
    underscore,
    number: i64,
    float: f64,
    eol,
    eof,
    ident: []const u8,
    percent,
    double_percent,
    string: []const u8,
    comment: []const u8,

    pub fn eql(a: Token, b: Token) bool {
        return (std.meta.activeTag(a) == std.meta.activeTag(b)) and switch (a) {
            .ident => |tokId| std.mem.eql(u8, tokId, b.ident),
            .string => |s| std.mem.eql(u8, s, b.string),
            .comment => |s| std.mem.eql(u8, s, b.comment),
            .number => |n| n == b.number,
            .float => |f| f == b.float,
            else => true,
        };
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "Token" {
    const token: Token = .colon;

    try expect(token == Token.colon);
}

const LiteralToken = struct {
    l: []const u8,
    t: Token,
};

const literalTokens = [_]LiteralToken{
    .{ .l = "->", .t = .arrow_right },
    .{ .l = ":", .t = .colon },
    .{ .l = "+", .t = .plus },
    .{ .l = "-", .t = .minus },
    .{ .l = "*", .t = .multiply },
    .{ .l = "<", .t = .less },
    .{ .l = ">", .t = .more },
    .{ .l = ",", .t = .comma },
    .{ .l = "==", .t = .double_assign },
    .{ .l = "=", .t = .assign },
    .{ .l = "&", .t = .ampersand },
    .{ .l = "@", .t = .at },
    .{ .l = "{", .t = .left_curly_bracket },
    .{ .l = "}", .t = .right_curly_bracket },
    .{ .l = "[", .t = .left_square_bracket },
    .{ .l = "]", .t = .right_square_bracket },
    .{ .l = "|", .t = .vertical_bar },
    .{ .l = "..", .t = .double_dot },
    .{ .l = "_", .t = .underscore },
    .{ .l = "\n", .t = .eol },
    .{ .l = "%%", .t = .double_percent },
    .{ .l = "%", .t = .percent },
};

// Lexer
allocator: Allocator,
tokens: []Token,
current: usize,

pub fn init(a: Allocator, reader: *std.Io.Reader) !Self {
    var content: [4 * 1024 * 1024]u8 = undefined;
    const n = try reader.readSliceShort(&content);

    const tokens = try parse_tokens(a, content[0..n]);
    std.log.debug("Lexer: tokens = {any}\n", .{tokens});

    return .{
        .allocator = a,
        .tokens = tokens,
        .current = 0,
    };
}

pub fn deinit(self: *Self) void {
    free_tokens(self.allocator, self.tokens);
    self.allocator.free(self.tokens);
}

pub fn top(self: *const Self) ?Token {
    if (self.current >= self.tokens.len) {
        return null;
    }
    return self.tokens[self.current];
}

pub fn pop(self: *Self) ?Token {
    if (self.current >= self.tokens.len) {
        return null;
    }
    const res = self.tokens[self.current];
    self.current += 1;
    return res;
}

pub fn drop(self: *Self) void {
    self.current += 1;
}

fn free_tokens(a: Allocator, tokens: []Token) void {
    for (tokens) |t| {
        switch (t) {
            .string => |s| a.free(s),
            .ident => |i| a.free(i),
            else => {},
        }
    }
}

fn parse_tokens(a: Allocator, content: []const u8) ![]Token {
    var list: std.ArrayListUnmanaged(Token) = .empty;
    errdefer {
        free_tokens(a, list.items);
        list.deinit(a);
    }
    var i: usize = 0;

    LOOP: while (i < content.len) {
        i = skip_whitespaces(content, i);
        // parse literal tokens
        for (literalTokens) |lt| {
            if (has_prefix(content[i..], lt.l)) {
                try list.append(a, lt.t);
                i += lt.l.len;
                continue :LOOP;
            }
        }

        // Parse float
        if (parse_utils.scan_float(f64, content[i..])) |res| {
            try list.append(a, Token{ .float = res.value });
            i += res.offset;
            continue :LOOP;
        }

        // Parse int
        if (parse_utils.scan_int(i64, content[i..])) |res| {
            try list.append(a, Token{ .number = res.value });
            i += res.offset;
            continue :LOOP;
        }

        // Parse identifiers
        if (parse_utils.scan_ident(content[i..])) |res| {
            const ident = try a.dupe(u8, res.value);
            try list.append(a, Token{ .ident = ident });
            i += res.offset;
            continue :LOOP;
        }

        // Parse strings
        if (try parse_utils.scan_string(content[i..])) |res| {
            const str = try a.dupe(u8, res.value);
            try list.append(a, Token{ .string = str });
            i += res.offset;
            continue :LOOP;
        }

        // Scan comments
        if (parse_utils.scan_comment(content[i..])) |res| {
            i += res.offset;
            continue :LOOP;
        }
        std.log.err("Unknown token here: {s}", .{ content[i..(i+64)]});
        return error.UnknownToken;
    }

    try list.append(a, Token.eof);
    return try list.toOwnedSlice(a);
}

test "parse_tokens" {
    const tokens = try parse_tokens(std.testing.allocator, "+ - -> : hello");
    defer {
        free_tokens(std.testing.allocator, tokens);
        std.testing.allocator.free(tokens);
    }

    try expect(tokensEql(tokens, &[_]Token{ .plus, .minus, .arrow_right, .colon, .{ .ident = "hello" }, .eof }));
}

test "parse_tokens numbers" {
    const tokens = try parse_tokens(std.testing.allocator, "1 23 4567 23.45 12.0 4..8");
    defer {
        free_tokens(std.testing.allocator, tokens);
        std.testing.allocator.free(tokens);
    }

    try expect(tokensEql(tokens, &[_]Token{
        .{ .number = 1 },
        .{ .number = 23 },
        .{ .number = 4567 },
        .{ .float = 23.45 },
        .{ .float = 12.0 },
        .{ .number = 4 },
        .double_dot,
        .{ .number = 8 },
        .eof,
    }));
}

test "parse_comments" {
    const tokens = try parse_tokens(std.testing.allocator, "foo # this is a comment\nbar\n# this is a comment too");
    defer {
        free_tokens(std.testing.allocator, tokens);
        std.testing.allocator.free(tokens);
    }

    try expect(tokensEql(tokens, &[_]Token{
        .{ .ident = "foo" },
        .eol,
        .{ .ident = "bar" },
        .eol,
        .eof,
    }));
}

test "parse_strings" {
    const tokens = try parse_tokens(std.testing.allocator, "foo = \"bar-baz\"");
    defer {
        free_tokens(std.testing.allocator, tokens);
        std.testing.allocator.free(tokens);
    }

    try expect(tokensEql(tokens, &[_]Token{
        .{ .ident = "foo" },
        .assign,
        .{ .string = "bar-baz" },
        .eof,
    }));
}

fn skip_whitespaces(content: []const u8, i: usize) usize {
    var ret = i;
    while (ret < content.len and content[ret] == ' ') {
        ret += 1;
    }
    return ret;
}

fn has_prefix(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) {
        return false;
    }
    return std.mem.eql(u8, str[0..prefix.len], prefix);
}

fn tokensEql(a: []const Token, b: []const Token) bool {
    if (a.len != b.len) {
        std.debug.print("Tokens lists have different length ({} != {}): {any} != {any}", .{a.len, b.len, a, b});
        return false;
    }
    for (a, 0..) |it, idx| {
        if (!it.eql(b[idx])) {
            std.debug.print("Tokens lists are different at index {}: {any} != {any}", .{idx, a, b});
            return false;
        }
    }
    return true;
}

test "has_prefix" {
    try expect(has_prefix("hello", "he"));
    try expect(!has_prefix("h", "he"));
    try expect(!has_prefix("world", "he"));
}
