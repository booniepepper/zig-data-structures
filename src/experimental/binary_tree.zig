const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

/// A very simple tree where every node is a tree.
/// This is primarily intended to be a backing data structure for more
/// sophisticated tree-based data structures with tuned insertion logic,
/// balancing, etc.
pub fn BinaryTree(comptime T: type) type {
    return struct {
        lhs: ?*Self = null,
        rhs: ?*Self = null,
        data: T,

        const Self = @This();

        /// Iterate over each child node, returning the count of all nodes including itself.
        /// This operation is O(N).
        pub fn count(self: *const Self) usize {
            var n: usize = 1;

            if (self.lhs) |lhs| n += lhs.count();
            if (self.rhs) |rhs| n += rhs.count();

            return n;
        }

        /// Reverse the tree starting from this node in-place. Why would anyone
        /// need this? Why does it come up in tech interviews?
        /// This operation is O(N).
        pub fn reverse(self: *Self) void {
            const temp = self.lhs;

            self.lhs = self.rhs;
            self.rhs = temp;

            if (self.lhs) |lhs| lhs.reverse();
            if (self.rhs) |rhs| rhs.reverse();
        }

        /// Sets both lhs and rhs to null.
        pub fn prune(self: *Self) void {
            self.lhs = null;
            self.rhs = null;
        }
    };
}

// TESTING

// Naive Math values to simulate an AST.
const Math = union(enum) {
    plus: void,
    minus: void,
    n: i32,

    // TODO: Add a simple parser?

    // Assumes that all branches are operators and their lhs/rhs are present. Assumes all leaves are numbers.
    fn resolve(tree: *BinaryTree(Math)) i32 {
        return switch (tree.data) {
            .plus => Math.resolve(tree.lhs.?) + Math.resolve(tree.rhs.?),
            .minus => Math.resolve(tree.lhs.?) - Math.resolve(tree.rhs.?),
            .n => |n| n,
        };
    }
};

test "1 + 2 = 3" {
    const T = BinaryTree(Math);

    var plus = T{ .data = .plus };
    try testing.expectEqual(@as(usize, 1), plus.count());

    var one = T{ .data = Math{ .n = 1 } };
    var two = T{ .data = Math{ .n = 2 } };

    plus.lhs = &one;
    plus.rhs = &two;

    try testing.expectEqual(@as(i32, 3), Math.resolve(&plus));
    try testing.expectEqual(@as(usize, 3), plus.count());
}

test "((5 - 4) + (0 + 2)) + ((6 - 2) + (2 + 3))" {
    const T = BinaryTree(Math);

    // We'll build up this:
    //        -
    //       / \
    //      +   +
    //    / |   | \
    //  -   +   -   +
    // / \ / \ / \ / \
    // 5 4 0 2 6 2 2 3

    var _one_lhs = T{ .data = .{ .n = 5 } };
    var _one_rhs = T{ .data = .{ .n = 4 } };
    var one = T{
        .data = .minus,
        .lhs = &_one_lhs,
        .rhs = &_one_rhs,
    };
    try testing.expectEqual(@as(i32, 1), Math.resolve(&one));
    try testing.expectEqual(@as(usize, 3), one.count());

    var _two_lhs = T{ .data = .{ .n = 0 } };
    var _two_rhs = T{ .data = .{ .n = 2 } };
    var two = T{
        .data = .plus,
        .lhs = &_two_lhs,
        .rhs = &_two_rhs,
    };
    try testing.expectEqual(@as(i32, 2), Math.resolve(&two));
    try testing.expectEqual(@as(usize, 3), two.count());

    var three = T{ .data = .plus, .lhs = &one, .rhs = &two };
    try testing.expectEqual(@as(i32, 3), Math.resolve(&three));
    try testing.expectEqual(@as(usize, 7), three.count());

    var _four_lhs = T{ .data = .{ .n = 6 } };
    var _four_rhs = T{ .data = .{ .n = 2 } };
    var four = T{
        .data = .minus,
        .lhs = &_four_lhs,
        .rhs = &_four_rhs,
    };
    try testing.expectEqual(@as(i32, 4), Math.resolve(&four));
    try testing.expectEqual(@as(usize, 3), four.count());

    var _five_lhs = T{ .data = .{ .n = 2 } };
    var _five_rhs = T{ .data = .{ .n = 3 } };
    var five = T{
        .data = .plus,
        .lhs = &_five_lhs,
        .rhs = &_five_rhs,
    };
    try testing.expectEqual(@as(i32, 5), Math.resolve(&five));
    try testing.expectEqual(@as(usize, 3), five.count());

    var nine = T{ .data = .plus, .lhs = &four, .rhs = &five };
    try testing.expectEqual(@as(i32, 9), Math.resolve(&nine));
    try testing.expectEqual(@as(usize, 7), nine.count());

    var negativeSix = T{ .data = .minus, .lhs = &three, .rhs = &nine };
    try testing.expectEqual(@as(i32, -6), Math.resolve(&negativeSix));
    try testing.expectEqual(@as(usize, 15), negativeSix.count());

    // Deep reversal will flip the subtraction operations.
    //        -
    //       / \
    //      +   +
    //    / |   | \
    //  +   -   +   -
    // / \ / \ / \ / \
    // 3 2 2 6 2 0 4 5

    negativeSix.reverse();
    var zero = negativeSix;
    try testing.expectEqual(@as(i32, 0), Math.resolve(&zero));
    try testing.expectEqual(@as(usize, 15), zero.count());
}
