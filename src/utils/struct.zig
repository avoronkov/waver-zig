const std = @import("std");

pub fn setStructField(obj: anytype, key: []const u8, value: anytype) !void {
    switch (@typeInfo(@TypeOf(obj.*))) {
        .@"struct" => |structInfo| {
            inline for (structInfo.fields) |field| {
                if (std.mem.eql(u8, field.name, key)) {
                    if (@FieldType(@TypeOf(obj.*), field.name) == @TypeOf(value)) {
                        @field(obj, field.name) = value;
                    } else {
                        return error.valueTypeMismatch;
                    }
                    return;
                }
            }
            return error.badKey;
        },
        else => @compileError("Unsupported object type: should be *struct"),
    }
}

// TODO tests.
test "set int value" {
    const A = struct { x: i64 = 0 };
    var a: A = .{};

    const value: i64 = 23;
    try setStructField(&a, "x", value);

    try std.testing.expectEqual(value, a.x);
}
