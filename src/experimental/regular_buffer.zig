
const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn RegularBuffer(comptime T: type, comptime slice_size: usize) type {

    if (slice_size == 0) {
        @compileError("Slice size must be greater than zero.");
    }

    return struct {

        const Self = @This();
        const ValueType = T;
        const SliceSize = slice_size;
        const DataSlice = []T;
        const ConstData = [] const T;

        const IteratorType = enum {
            slice, vector
        };

        data: DataSlice,
        capacity: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .data = &[_]T{},
                .capacity = 0,
                .allocator = allocator,
            };
        }

        pub fn itemCount(self: *const Self) usize {
            return self.data.len / SliceSize;
        }

        pub fn initCapacity(allocator: Allocator, count: usize) Allocator.Error!Self {
            var self = Self.init(allocator);
            try self.ensureTotalCapacity(count * SliceSize);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.allocatedSlice());
            self.capacity = 0;
            self.data = &[_]T{ };
        }

        pub fn fromOwnedSlice(allocator: Allocator, slice: DataSlice) Self {
            return Self{
                .data = slice,
                .capacity = slice.len,
                .allocator = allocator,
            };
        }

        pub fn toOwnedSlice(self: *Self) Allocator.Error!DataSlice {
            const allocator = self.allocator;

            const old_memory = self.allocatedSlice();
            if (allocator.resize(old_memory, self.data.len)) {
                const result = self.data;
                self.* = init(allocator);
                return result;
            }
            const new_memory = try allocator.alloc(T, self.data.len);
            @memcpy(new_memory, self.data);
            @memset(self.data, undefined);
            self.clearAndFree();
            return new_memory;
        }

        pub fn get(self: *const Self, index: usize) ConstData {
            const pos = index * SliceSize;
            const end = pos + SliceSize;
            std.debug.assert(end <= self.data.len);
            return self.data[pos..end];
        }

        pub fn set(self: *Self, index: usize, slice: ConstData) void {
            const pos = index * SliceSize;
            const end = pos + SliceSize;
            std.debug.assert(end <= self.data.len);
            @memcpy(self.data[pos..end], slice);
        }

        pub fn clone(self: Self) Allocator.Error!Self {
            var cloned = try Self.initCapacity(self.allocator, self.capacity);
            if (self.data.len > 0) {
                 @memcpy(cloned.data, self.data);
            }
            return cloned;
        }

        pub fn append(self: *Self, slice: ConstData) Allocator.Error!void {
            std.debug.assert(slice.len == SliceSize);
            try self.ensureUnusedCapacity(1);
            const end = self.data.len + SliceSize;
            @memcpy(self.data.ptr[self.data.len..end], slice);
            self.data.len = end;
        }

        pub fn allocatedSlice(self: Self) DataSlice {
            return self.data.ptr[0..self.capacity];
        }

        pub fn resize(self: *Self, new_count: usize) Allocator.Error!void {
            try self.ensureTotalCapacity(new_count * SliceSize);
            self.data.len = new_count;
        }
        
        // this method is private because the new_capacity is calculated situationally.
        fn ensureTotalCapacity(self: *Self, new_capacity: usize) Allocator.Error!void {

            if (self.capacity >= new_capacity) 
                return;

            const old_memory = self.allocatedSlice();
            if (self.allocator.resize(old_memory, new_capacity)) {
                self.capacity = new_capacity;
            } else {
                const new_memory = try self.allocator.alloc(T, new_capacity);
                @memcpy(new_memory[0..self.data.len], self.data);
                self.allocator.free(old_memory);
                self.data.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        pub fn ensureUnusedCapacity(self: *Self, additional_count: usize) Allocator.Error!void {
            return self.ensureTotalCapacity(self.data.len + (additional_count * SliceSize));
        }

        const ForwardIterator = struct {
            ptr: *const Self,
            idx: usize = 0,
            pub inline fn next(self: *@This()) ?ConstData {
                const last = self.idx;
                return if (last < self.ptr.data.len) blk: { 
                    self.idx += SliceSize;
                    break :blk self.ptr.data[last..self.idx];
                } else null;
            }
        };

        pub fn iterator(self: *const Self) ForwardIterator {
            return .{ .ptr = self, .idx = 0 };
        }
    };
}

// Some types may be vectorizable. Because the slice size is known
// at compile time, we can create a convenience iterator to return
// vectors instead of slices.

inline fn VectorIteratorType(comptime T: type) type {
    return struct {
        const SliceSize = T.SliceSize;
        const ValueType = T.ValueType;
        ptr: *const T,
        idx: usize = 0,
        pub inline fn next(self: *@This()) ?@Vector(SliceSize, ValueType) {
            const last = self.idx;
            return if (last < self.ptr.data.len) blk: { 
                self.idx += SliceSize;
                const slice = self.ptr.data[last..self.idx];
                break :blk slice[0..SliceSize].*;
            } else null;
        }
    };
}

// Helper function for creating VectorIteratorType
pub inline fn VectorIterator(buffer: anytype) VectorIteratorType(@TypeOf(buffer.*)) {
    return .{ .ptr = buffer, .idx = 0 };
}