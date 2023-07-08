const std = @import("std");
pub const EvictingStack = @import("experimental/evicting_stack.zig").EvictingStack;

test {
    std.testing.refAllDecls(@This());
}
