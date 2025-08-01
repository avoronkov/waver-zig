const waveform = @import("./waveform.zig");
const sample = @import("./sample.zig");
const Note = @import("./note.zig");
const EofError = @import("./wave.zig").EofError;

pub const WaveInput = union(enum) {
    waveform: waveform.WaveForm,
    sample: sample.Sample,
};

pub fn value(input: *const WaveInput, t: f64, note: Note) EofError!f64 {
    return switch (input.*) {
        .sample => |s| s.value(t, note),
        .waveform => |wf| wf(t, note),
    };
}

pub fn copy(in: *const WaveInput) !WaveInput {
    return switch (in.*) {
        .sample => |s| WaveInput{ .sample = try s.copy() },
        .waveform => |wf| WaveInput{ .waveform = wf },
    };
}
