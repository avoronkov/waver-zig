const std = @import("std");
const parse_utils = @import("./parse_utils.zig");
const primitives = @import("./primitives.zig");

const Allocator = std.mem.Allocator;

const Ident = primitives.Ident;

const Self = @This();

pub const Token = union(enum) {
    colon,
    plus,
    minus,
    multiply,
    less,
    more,
    arrow_right,
    coma,
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
    number: i64,
    float: f64,
    eol,
    eof,
    ident: Ident,
    percent,
    double_percent,
    string: []const u8,
    comment: []const u8,
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
    .{ .l = ",", .t = .coma },
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
    .{ .l = "\n", .t = .eol },
    .{ .l = "%%", .t = .double_percent },
    .{ .l = "%", .t = .percent },
};

// Lexer
allocator: Allocator,
tokens: []Token,
current: usize,

pub fn init(a: Allocator, file: []const u8) !Self {
    const content = try std.fs.cwd().readFileAlloc(a, file, 4 * 1024 * 1024);
    defer a.free(content);

    const tokens = try parse_tokens(a, content);
    std.debug.print("Lexer: tokens = {any}\n", .{tokens});

    return .{
        .allocator= a,
        .tokens = tokens,
        .current = 0,
    };
}

pub fn deinit(self: *Self) void {
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

fn parse_tokens(a: Allocator, content: []const u8) ![]Token {
    var list = std.ArrayListUnmanaged(Token){};
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
        if (try parse_utils.scan_ident(content[i..])) |res| {
            try list.append(a, Token{ .ident = res.value });
            i += res.offset;
            continue :LOOP;
        }

        // Scan comments
        if (parse_utils.scan_comment(content[i..])) |res| {
            i += res.offset;
            continue :LOOP;
        }

        return error.UnknownToken;
    }

    try list.append(a, Token.eof);
    return try list.toOwnedSlice(a);
}

test "parse_tokens" {
    const tokens = try parse_tokens(std.testing.allocator, "+ - -> : hello");
    defer std.testing.allocator.free(tokens);

    std.debug.print("parsed tokens: {any}\n", .{tokens});
    try expect(tokens.len == 6);
}

test "parse_tokens numbers" {
    const tokens = try parse_tokens(std.testing.allocator, "1 23 4567 23.45 12.0");
    defer std.testing.allocator.free(tokens);

    std.debug.print("parsed tokens: {any}\n", .{tokens});
    try expectEqual(6, tokens.len);
    try expect(tokens[0].number ==  1);
    try expect(tokens[1].number == 23);
    try expect(tokens[2].number == 4567);
    try expect(tokens[3].float == 23.45);
    try expect(tokens[4].float == 12.0);
    try expect(tokens[5] == Token.eof);
}

test "parse_comments" {
    const tokens = try parse_tokens(std.testing.allocator, "foo # this is a comment\nbar\n# this is a comment too");
    defer std.testing.allocator.free(tokens);

    std.debug.print("parsed tokens: {any}\n", .{tokens});
    try expectEqual(5, tokens.len);
    try expectEqualStrings("foo", tokens[0].ident.string());
    try expectEqual(.eol, tokens[1]);
    try expectEqualStrings("bar", tokens[2].ident.string());
    try expectEqual(.eol, tokens[3]);
    try expectEqual(.eof, tokens[4]);
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

test "has_prefix" {
    try expect(has_prefix("hello", "he"));
    try expect(!has_prefix("h", "he"));
    try expect(!has_prefix("world", "he"));
}
