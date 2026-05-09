pub fn takeNChars(str: []const u8, i: usize, n: usize) []const u8 {
    return if (i + n < str.len)
        str[i .. i + n]
    else
        str[i..];
}
