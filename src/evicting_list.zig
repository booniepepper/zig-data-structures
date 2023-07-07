const std = @import("std");
const Allocator = std.mem.Allocator;

/// A list of items in memory. If the number of items inserted ever
/// exceeds capacity, the oldest items are dropped.
pub fn EvictingList(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        first: usize = 0,
        next: usize = 0,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        pub fn toOwnedSlice(self: Self, allocator: Allocator) ![]const T {
            const naiveEnd = self.first + self.len;
            if (naiveEnd <= capacity) return self.items[self.first..naiveEnd];

            // TODO: Can this be done without an allocator though?
            var buf = try allocator.alloc(T, self.len);

            const firstHalf = self.items[self.first..];
            const lastHalf = self.items[0..self.next];

            std.mem.copyForwards(T, buf, firstHalf);
            std.mem.copyForwards(T, buf[firstHalf.len..], lastHalf);
            return buf[0..];
        }

        pub fn append(self: *Self, item: T) void {
            self.items[self.next] = item;

            self.next = @mod(self.next + 1, capacity);

            self.len += 1;

            if (self.len > self.items.len) {
                self.len = self.items.len;
                self.first = @mod(self.first + 1, capacity);
            }
        }
    };
}

test "list of three bytes" {
    const L = EvictingList(u8, 3);
    var list = L.init();

    try std.testing.expectEqualSlices(u8, "", try list.toOwnedSlice(std.testing.allocator));

    list.append('a');
    try std.testing.expectEqualSlices(u8, "a", try list.toOwnedSlice(std.testing.allocator));

    list.append('b');
    try std.testing.expectEqualSlices(u8, "ab", try list.toOwnedSlice(std.testing.allocator));

    list.append('c');
    try std.testing.expectEqualSlices(u8, "abc", try list.toOwnedSlice(std.testing.allocator));

    list.append('d');
    try std.testing.expectEqualSlices(u8, "bcd", try list.toOwnedSlice(std.testing.allocator));

    list.append('e');
    list.append('f');
    try std.testing.expectEqualSlices(u8, "def", try list.toOwnedSlice(std.testing.allocator));
}
