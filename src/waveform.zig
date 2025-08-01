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

pub fn triangle(t: f64, note: Note) !f64 {
    if (t > note.dur) {
        return error.Eof;
    }
    // Start from 0-point.
    const y = (t * note.freq) + 0.25;
    const yd = y - std.math.floor(y);
    return if (yd < 0.5)
        -1 + 4 * yd
    else
        1 - 4 * (yd - 0.5);
}

pub fn square(t: f64, note: Note) !f64 {
    if (t > note.dur) {
        return error.Eof;
    }

    const y = t * note.freq;
    return if (y - std.math.floor(y) < 0.5) 1 else -1;
}

pub fn saw(t: f64, note: Note) !f64 {
    if (t > note.dur) {
        return error.Eof;
    }

    const y = t * note.freq + 0.25;
    const yd = y - std.math.floor(y);
    return yd * 2 - 1;
}

pub fn semisine(t: f64, note: Note) !f64 {
    if (t > note.dur) {
        return error.Eof;
    }

    const x = 2 * std.math.pi * note.freq * t;
    return 2 * @abs(std.math.sin(x)) - 1;
}


pub const waveforms = std.static_string_map.StaticStringMap(WaveForm).initComptime(.{
    .{ "sine", sine },
    .{ "triangle", triangle },
    .{ "square", square },
    .{ "saw", saw },
    .{ "semisine", semisine },
});
