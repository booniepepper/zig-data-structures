
const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn IrregularBuffer(comptime T: type) type {

    return struct {

        const Self = @This();
        const DataSlice = []T;
        const ConstData = [] const T;
        const IdxsSlice = []IndexPair;
        const ConstIdxs = [] const IndexPair;

        const IndexPair = struct {
            lhs: usize,
            rhs: usize,  
        };

        const ForwardIterator = struct {
            ptr: *const Self,
            idx: usize = 0,
            pub fn next(self: *@This()) ?ConstData {
                const last = self.idx;
                return if (last < self.ptr.idxs.len) blk: { 
                    self.idx += 1;
                    break :blk self.ptr.get(last);
                } else null;
            }
        };

        data: DataSlice,
        idxs: IdxsSlice,
        data_capacity: usize,
        idxs_capacity: usize,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .data = &[_]T{},
                .idxs = &[_]IndexPair{},
                .data_capacity = 0,
                .idxs_capacity = 0,
                .allocator = allocator,
            };
        }

        pub fn itemCount(self: *const Self) usize {
            return self.idxs.len;
        }

        pub fn initCapacity(allocator: Allocator, data_size: usize, segments: usize) Allocator.Error!Self {
            var self = Self.init(allocator);
            try self.ensureTotalCapacity(data_size, segments);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.allocatedData());
            self.allocator.free(self.allocatedIdxs());
            self.data_capacity = 0;
            self.idxs_capacity = 0;
            self.data = &[_]T{ };
            self.idxs = &[_]IndexPair{ };
        }

        pub fn get(self: *const Self, index: usize) ConstData {
            std.debug.assert(index <= self.idxs.len);
            const pair = self.idxs[index];
            return self.data[pair.lhs..pair.rhs];
        }

        // if you try to append a value that is larger than the 
        // selected segment, we have to resize to make it work.
        pub fn set(self: *Self, index: usize, slice: ConstData) Allocator.Error!void {
            std.debug.assert(index < self.idxs.len);

            const pair = self.idxs[index];

            const old_len = (pair.rhs - pair.lhs);

            // easiest case - it already fits in the slot
            if (old_len >= slice.len) {
                // reduce the rhs if it's longer than the new length
                if (old_len > slice.len) {
                    self.idxs[index].rhs = pair.lhs + slice.len;
                }
                // copy into place (potentially leaves a gap)
                return @memcpy(self.data[pair.lhs..pair.lhs + slice.len], slice);
            }

            // we're now out of bounds, so we calculate new
            // capacities and adjust the idxs boundaries
            const dif_len = (slice.len - old_len);
            const new_len = self.data.len + dif_len;
            try self.ensureUnusedCapacity(new_len, 0);

            if (index == (self.idxs.len - 1)) {
                @memcpy(self.data.ptr[pair.lhs..new_len], slice);
            }  
            else { // copy entire buffer up to the right-side
                var old_pos = self.data.ptr[pair.rhs..self.data.len];
                var new_pos = self.data.ptr[pair.rhs + dif_len..new_len];
                std.mem.copyBackwards(u8, new_pos, old_pos);

                // fill in the expanded slot with the new slice
                @memcpy(self.data[pair.lhs..pair.lhs + slice.len], slice);            

                // increment new positions in the idxs buffer
                for (self.idxs[index + 1..]) |*idx| {
                    idx.lhs += dif_len;
                    idx.rhs += dif_len;
                }            
            }
            // make final adjustment to boundaries
            self.idxs[index].rhs += dif_len;
            self.data.len += dif_len;
        }

        pub fn clone(self: Self) Allocator.Error!Self {
            var cloned = try Self.initCapacity(self.allocator, self.data_capacity, self.idxs_capacity);
            if (self.data.len > 0) {
                 @memcpy(cloned.data, self.data);
                 @memcpy(cloned.idxs, self.idxs);
            }
            return cloned;
        }

        pub fn append(self: *Self, slice: ConstData) Allocator.Error!void {
            try self.ensureUnusedCapacity(slice.len, 1);

            // calculate new segment offsets
            const old_end = self.data.len;
            const new_end = old_end + slice.len;

            // copy memory to the end of the data buffer
            @memcpy(self.data.ptr[old_end..new_end], slice);

            // append new index pair for data segment
            self.idxs.ptr[self.idxs.len] = .{ .lhs = old_end, .rhs = new_end };

            // reset slice boundaries
            self.data.len = new_end;
            self.idxs.len += 1;
        }

        pub fn allocatedData(self: Self) DataSlice {
            return self.data.ptr[0..self.data_capacity];
        }

        pub fn allocatedIdxs(self: Self) IdxsSlice {
            return self.idxs.ptr[0..self.idxs_capacity];
        }

        pub fn resize(self: *Self, data_size: usize, idxs_size: usize) Allocator.Error!void {
            try self.ensureTotalCapacity(data_size, idxs_size);
            self.data.len = data_size;
            self.idxs.len = idxs_size;
        }
        
        fn ensureTotalCapacity(self: *Self, data_capacity: usize, idxs_capacity: usize) Allocator.Error!void {

            // check data capacity...
            if (self.data_capacity < data_capacity) {
                const old_memory = self.allocatedData();
                if (self.allocator.resize(old_memory, data_capacity)) {
                    self.data_capacity = data_capacity;
                } else {
                    const new_memory = try self.allocator.alloc(T, data_capacity);
                    @memcpy(new_memory[0..self.data.len], self.data);
                    self.allocator.free(old_memory);
                    self.data.ptr = new_memory.ptr;
                    self.data_capacity = new_memory.len;
                }
            }

            // check idxs capacity...
            if (self.idxs_capacity < idxs_capacity) {
                const old_memory = self.allocatedIdxs();
                if (self.allocator.resize(old_memory, idxs_capacity)) {
                    self.idxs_capacity = idxs_capacity;
                } else {
                    const new_memory = try self.allocator.alloc(IndexPair, idxs_capacity);
                    @memcpy(new_memory[0..self.idxs.len], self.idxs);
                    self.allocator.free(old_memory);
                    self.idxs.ptr = new_memory.ptr;
                    self.idxs_capacity = new_memory.len;
                }
            }
        }

        pub fn ensureUnusedCapacity(self: *Self, data_count: usize, idxs_count: usize) Allocator.Error!void {
            return self.ensureTotalCapacity(self.data.len + data_count, self.idxs.len + idxs_count);
        }

        pub fn iterator(self: *const Self) ForwardIterator {
            return .{ .ptr = self, .idx = 0 };
        }
    };
}

pub fn main() !void {  

    var GPA = std.heap.GeneralPurposeAllocator(.{}){ };

    var buffer = try IrregularBuffer(u8).initCapacity(GPA.allocator(), 100, 10);

    defer { 
        buffer.deinit();
        if (GPA.deinit() == .leak) {
            @panic("LEAK DETECTED!");
        }
    }

    try buffer.append("Hello");
    try buffer.append("World");
    try buffer.append("My");
    try buffer.append("Name");
    try buffer.append("Is");
    try buffer.append("Andrew");

    var iter = buffer.iterator();
    while (iter.next()) |data| {
        std.debug.print("\n{s}\n", .{ data });
    }

    //std.debug.print("\n{s} {s}!\n\n", .{ 
    //    buffer.get(0), buffer.get(1)    
    //});

    //std.debug.print("\n{},{} : {},{}\n\n", .{
    //    buffer.idxs[0].lhs, buffer.idxs[0].rhs,    
    //    buffer.idxs[1].lhs, buffer.idxs[1].rhs,    
    //});

    //try buffer.set(0, "Goodbye");

    //std.debug.print("\n{s} {s}!\n\n", .{ 
    //    buffer.get(0), buffer.get(1)    
    //});

    //std.debug.print("\n{},{} : {},{}\n\n", .{
    //    buffer.idxs[0].lhs, buffer.idxs[0].rhs,    
    //    buffer.idxs[1].lhs, buffer.idxs[1].rhs,    
    //});

    //try buffer.set(1, "for now");

    //std.debug.print("\n{s} {s}!\n\n", .{ 
    //    buffer.get(0), buffer.get(1)    
    //});

    //std.debug.print("\n{},{} : {},{}\n\n", .{
    //    buffer.idxs[0].lhs, buffer.idxs[0].rhs,    
    //    buffer.idxs[1].lhs, buffer.idxs[1].rhs,    
    //});
}