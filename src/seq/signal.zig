const primitives = @import("../pelia/primitives.zig");

pub const Signal = struct {
    time: ?f64 = null,
    instrument: primitives.Ident,
    freq: f64,
    duration_bits: i64,
    amplitude: f64,
};
