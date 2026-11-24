const std = @import("std");

pub fn setStructField(obj: anytype, key: []const u8, value: anytype) !void {
    switch (@typeInfo(@TypeOf(obj.*))) {
        .@"struct" => |structInfo| {
            inline for (structInfo.field_names) |field_name| {
                if (std.mem.eql(u8, field_name, key)) {
                    if (@FieldType(@TypeOf(obj.*), field_name) == @TypeOf(value)) {
                        @field(obj, field_name) = value;
                        // TODO convert int to float
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
