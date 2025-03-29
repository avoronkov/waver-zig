const std = @import("std");
const Note = @import("./note.zig");

pub const WaveForm = *const fn (t: f64, note: Note) error{Eof}!f64;

pub fn sine(t: f64, note: Note) !f64 {
    if (t > note.dur) {
        return error.Eof;
    }
    const x = 2 * std.math.pi * t * note.freq;
    const res = note.amp * std.math.sin(x);
    return res;
}

pub const waveforms = std.static_string_map.StaticStringMap(WaveForm).initComptime(.{
    .{ "sine", sine },
});
