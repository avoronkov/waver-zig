const std = @import("std");

pub const notes = std.StaticStringMap(i64).initComptime(.{
    .{ "C1", 1 },
    .{ "Cs1", 2 },
    .{ "Db1", 2 },
    .{ "D1", 3 },

    .{ "C2", 13 },

    .{ "C3", 25 },
    .{ "A3", 34 },

    .{ "C4", 37 },
    .{ "A4", 46 },
});

// 12th root of 2.0
const half_step = 1.0594630943593;

pub const frequencies = [_]f64{
    0.0,
    0.0, // C1
    0.0, // Cs1
    0.0, // D1
    0.0, // Ds1
    0.0, // E1
    0.0, // F1
    0.0, // Fs1
    0.0, // G1
    55.0 / half_step, // Gs1
    55.0, // A1
    55.0 * half_step, // As1
    0.0, // B1

    0.0, // C2
    0.0, // Cs2
    0.0, // D2
    0.0, // Ds2
    0.0, // E2
    0.0, // F2
    0.0, // Fs2
    0.0, // G2
    110.0 / half_step, // Gs2
    110.0, // A2
    110.0 * half_step, // As2
    0.0, // B2

    0.0, // C3
    0.0, // Cs3
    0.0, // D3
    0.0, // Ds3
    0.0, // E3
    0.0, // F3
    0.0, // Fs3
    0.0, // G3
    220.0 / half_step, // Gs3
    220.0, // A3
    220.0 * half_step, // As3
    0.0, // B3

    0.0, // C4
    0.0, // Cs4
    0.0, // D4
    0.0, // Ds4
    0.0, // E4
    0.0, // F4
    0.0, // Fs4
    0.0, // G4
    440.0 / half_step, // Gs4
    440.0, // A4
    440.0 * half_step, // As4
    0.0, // B4
};
