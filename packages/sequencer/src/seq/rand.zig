const std = @import("std");
const DefaultPrng = std.Random.DefaultPrng;
const Random = std.Random;

// SAFETY: initialized by init()
pub var prng: DefaultPrng = undefined;

// SAFETY: initialized by init()
pub var random: Random = undefined;

pub fn init() void {
    const ts: u128 = @bitCast(std.time.nanoTimestamp());
    const seed: u64 = @truncate(ts);

    prng = DefaultPrng.init(seed);
    random = prng.random();
}
