const std = @import("std");

pub fn setStructField(obj: anytype, key: []const u8, value: anytype) !void {
    switch (@typeInfo(@TypeOf(obj.*))) {
        .@"struct" => |structInfo| {
            inline for (structInfo.field_names) |field_name| {
                if (std.mem.eql(u8, field_name, key)) {
                    if (@FieldType(@TypeOf(obj.*), field_name) == @TypeOf(value)) {
                        @field(obj, field_name) = value;
                    } else if (@FieldType(@TypeOf(obj.*), field_name) == f64 and @TypeOf(value) == i64) {
                        // Convert i64 to f64.
                        const fvalue: f64 = @floatFromInt(value);
                        @field(obj, field_name) = fvalue;
                    } else {
                        std.log.err("Cannot assign {any} to field {s} of type {any}", .{value, key, @FieldType(@TypeOf(obj.*), field_name)});
                        return error.valueTypeMismatch;
                    }
                    return;
                }
            }
            std.log.err("Field {s} not found in type {any}", .{key, @TypeOf(obj.*)});
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

test "set int value to float field" {
    const A = struct { x: f64 = 0 };
    var a: A = .{};

    const value: i64 = 56;
    try setStructField(&a, "x", value);

    try std.testing.expectEqual(a.x, 56);
}
