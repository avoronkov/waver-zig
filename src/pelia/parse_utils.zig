const std = @import("std");
const primitives = @import("./primitives.zig");
const Ident = primitives.Ident;

fn ScanResult(comptime T: type) type {
    return struct {
        value: T,
        offset: usize,
    };
}

pub fn scan_int(comptime T: type, s: []const u8) ?ScanResult(T) {
    const n = for (0.., s) |i, c| {
        if (i == 0 and c == '-') {
            continue;
        }
        if (c < '0' or c > '9') {
            break i;
        }
    } else s.len;
    if (n == 0) {
        return null;
    }
    const value = std.fmt.parseInt(T, s[0..n], 10) catch |e| std.debug.panic("parseInt('{s}') failed: {!}\n", .{ s[0..n], e });
    return .{
        .value = value,
        .offset = n,
    };
}

test "scan_int: success" {
    const T = struct {
        s: []const u8,
        v: i32,
        o: usize,
    };

    const tests = [_]T{
        .{
            .s = "1234asdf",
            .v = 1234,
            .o = 4,
        },
        .{
            .s = "2345",
            .v = 2345,
            .o = 4,
        },
        .{
            .s = "-3456",
            .v = -3456,
            .o = 5,
        },
    };

    for (tests) |t| {
        const res = scan_int(i32, t.s) orelse unreachable;
        try std.testing.expectEqual(t.v, res.value);
        try std.testing.expectEqual(t.o, res.offset);
    }
}

test "empty string" {
    const res = scan_int(i32, "");
    try std.testing.expectEqual(null, res);
}

test "invalid integer" {
    const res = scan_int(i32, "asdf");
    try std.testing.expectEqual(null, res);
}

pub fn scan_float(comptime T: type, s: []const u8) ?ScanResult(T) {
    var dot = false;
    const n = for (0.., s) |i, c| {
        if (i == 0 and c == '-') {
            continue;
        }
        if (c == '.') {
            if (dot) {
                return null;
            }
            dot = true;
            continue;
        }
        if (c < '0' or c > '9') {
            break i;
        }
    } else s.len;
    if (n == 0 or !dot) {
        return null;
    }
    const value = std.fmt.parseFloat(T, s[0..n]) catch |e| std.debug.panic("parseFloat('{s}' failed: {!}\n", .{ s[0..n], e });
    return .{
        .value = value,
        .offset = n,
    };
}
test "float: success" {
    const Test = struct {
        s: []const u8,
        value: f64,
        offset: usize,
    };

    const tests = [_]Test{
        .{
            .s = "-12.25",
            .value = -12.25,
            .offset = 6,
        },
        .{
            .s = "10.0",
            .value = 10.0,
            .offset = 4,
        },
        .{
            .s = "13.05asdf",
            .value = 13.05,
            .offset = 5,
        },
        .{
            .s = "13.",
            .value = 13.0,
            .offset = 3,
        },
    };
    for (tests) |t| {
        const res = scan_float(f64, t.s) orelse unreachable;
        try std.testing.expectEqual(t.value, res.value);
        try std.testing.expectEqual(t.offset, res.offset);
    }
}

test "float: error" {
    const T = struct {
        s: []const u8,
        e: anyerror,
    };

    const tests = [_]T{
        .{
            .s = "123",
            .e = error.InvalidCharacter,
        },
    };

    for (tests) |t| {
        try std.testing.expectEqual(null, scan_float(f64, t.s));
    }
}

pub fn scan_ident(s: []const u8) !?ScanResult(Ident) {
    const n = for (0.., s) |i, c| {
        if (i == 0) {
            if (!(c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z')) {
                break i;
            }
        } else if (!(c >= 'a' and c <= 'z' or c >= 'A' and c <= 'Z' or c >= '0' and c <= '9')) {
                break i;
            }
    } else s.len;
    if (n == 0) {
        return null;
    }
    const ident = try Ident.init(s[0..n]);
    return .{
        .value = ident,
        .offset = n,
    };
}

test "scan_ident success" {
    const res = try scan_ident("hello123+") orelse unreachable;
    try std.testing.expectEqualStrings("hello123", res.value.string());
    try std.testing.expectEqual(8, res.offset);
}

pub fn scan_comment(s: []const u8) ?ScanResult(void) {
   if (s.len > 0 and s[0] == '#') {
       if (std.mem.indexOf(u8, s, "\n")) |idx| {
           return .{
               .value = {},
               .offset = idx,
           };
       }
       return .{
           .value = {},
           .offset = s.len,
       };
   } else return null;
}

pub fn scan_string(s: []const u8) !?ScanResult([]const u8) {
    const n = for (0.., s) |i, c| {
        if (i == 0) {
            if (c != '"') {
                return null;
            }
            continue;
        }
        if (c == '"') {
            break i;
        }
    } else {
        return error.UnexpectedEof;
    };
    return .{
        .value = s[1..n],
        .offset = n+1,
    };
}
