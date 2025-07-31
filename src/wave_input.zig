const waveform = @import("./waveform.zig");
const sample = @import("./sample.zig");
const Note = @import("./note.zig");
const EofError = @import("./wave.zig").EofError;

pub const WaveInput = union(enum) {
    waveform: waveform.WaveForm,
    sample: sample.Sample,
};

pub fn value(input: WaveInput, t: f64, note: Note) EofError!f64 {
    return switch (input) {
        .sample => |s| s.value(t, note),
        .waveform => |wf| wf(t, note),
    };
}
