const std = @import("std");
const Spec = @import("./spec.zig");
const seq = @import("seq");

pub fn specification() Spec {
    return .{
        .waves = seq.waveforms.keys(),
    };
}
