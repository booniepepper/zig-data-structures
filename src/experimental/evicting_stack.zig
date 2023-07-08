const std = @import("std");
const Allocator = std.mem.Allocator;

/// A list of items. When inserting an item exceeds capacity, the oldest item
/// is dropped.
pub fn EvictingStack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        items: [capacity]T = undefined,
        first: usize = 0,
        len: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Appends an item to the stack. If appending would go above capacity,
        /// the oldest element is replaced and returned.
        pub fn push(self: *Self, item: T) ?T {
            // We'll insert at index i
            const i = @mod(self.first + self.len, capacity);

            // The next index after i, possibly wrappring around
            const j = @mod(i + 1, capacity);

            var dropped: ?T = null;

            if (self.len == capacity) {
                dropped = self.items[i];
                self.first = j;
            } else {
                self.len += 1;
            }

            self.items[i] = item;

            return dropped;
        }

        /// Pops an item from the stack. Returns null if there are no items
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;

            self.len -= 1;

            const last = @mod(capacity + self.first + self.len, capacity);
            return self.items[last];
        }
    };
}

test "list of three bytes" {
    const L = EvictingStack(u8, 3);
    var list = L.init();

    try std.testing.expectEqualSlices(u8, "", list.items[0..list.len]);

    var dropped = list.push('a');
    try std.testing.expect(null == dropped);
    try std.testing.expectEqualSlices(u8, "a", list.items[0..list.len]);

    dropped = list.push('b');
    try std.testing.expect(null == dropped);
    try std.testing.expectEqualSlices(u8, "ab", list.items[0..list.len]);

    dropped = list.push('c');
    try std.testing.expect(null == dropped);
    try std.testing.expectEqualSlices(u8, "abc", &list.items);

    dropped = list.push('d');
    try std.testing.expect('a' == dropped);
    try std.testing.expectEqualSlices(u8, "dbc", &list.items);

    dropped = list.push('e');
    try std.testing.expect('b' == dropped);
    try std.testing.expectEqualSlices(u8, "dec", &list.items);

    dropped = list.push('f');
    try std.testing.expect('c' == dropped);
    try std.testing.expectEqualSlices(u8, "def", &list.items);

    try std.testing.expect('f' == list.pop().?);
    try std.testing.expect('e' == list.pop().?);
    try std.testing.expect('d' == list.pop().?);
    try std.testing.expect(null == list.pop());
}
