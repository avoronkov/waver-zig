const waveform = @import("./waveform.zig");
const sample = @import("./sample.zig");

pub const WaveInput = union(enum) {
    waveform: waveform.WaveForm,
    sample: sample.Sample,
};
