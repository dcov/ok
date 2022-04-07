const std = @import("std");

const tokenizer = @import("./tokenizer.zig");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test "include all tests" {
    _ = tokenizer;
}
