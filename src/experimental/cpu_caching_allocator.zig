
const std = @import("std");

const OrderedCache = struct {

    const Self = @This();

    const CacheType = std.ArrayList(CacheBlock);

    const CacheBlock = struct {
        data: []u8 = undefined,
        used: bool = false,
    };

    cache: CacheType,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .cache = CacheType.init(allocator) };
    }
    pub fn deinit(self: *Self, allocator: *std.mem.Allocator) void {
        for(0..self.size()) |i| {
            allocator.free(self.itemData(i));
        }
        self.cache.deinit();
    }
    pub fn clear(self: *Self, allocator: *std.mem.Allocator) void {
        for(0..self.size()) |i| {
            allocator.free(self.itemData(i));
        }
        // Calling resize will test for capacity and then
        // set the length to the new size. Since we're only
        // going to zero, we don't need to check for capacity.
        self.cache.items.len = 0;
    }
    
    pub inline fn size(self: *const Self) usize {
        return self.cache.items.len;
    }
    inline fn itemUsed(self: *const Self, i: usize) bool {
        return self.cache.items[i].used;
    }
    inline fn itemData(self: *const Self, i: usize) []u8 {
        return self.cache.items[i].data;
    }
    inline fn itemSize(self: *const Self, i: usize) usize {
        return self.cache.items[i].data.len;
    }
    inline fn setUsed(self: *const Self, i: usize, used: bool) void {
        self.cache.items[i].used = used;
    }

    pub fn lowerBoundSize(self: *const Self, n: usize) usize {
        var len = self.size();
        var idx: usize = 0;
        while (len > 0) {
            const half = (len >> 1);
            const mid = half + idx;
            if (self.itemSize(mid) < n) {
                idx = mid + 1;
                len = (len - half) - 1;
            } else {
                len = half;
            }
        }
        return idx;
    }

    fn scanForUnused(self: *const Self, idx: usize, n: usize) ?[]u8 {

        // heuristic: requests cannot grab allocations 2x their size
        const limit = n <<| 1;
        
        var i = idx;
        while ((i < self.size()) and (self.itemSize(i) <= limit)) : (i += 1) {
            if (!self.itemUsed(i)) {
                self.setUsed(i, true);
                return self.itemData(i);
            }
        }
        return null;
    }

    pub fn locateMemory(self: *const Self, data: []u8) ?usize {

        // If this function succeeds, it returns an
        // index within the cache-size boundary that
        // relates to the index of the data argument

        if ((self.size() == 0) or (data.len == 0)) {
            return null;
        }

        const limit = data.len <<| 1;

        var i = if (data.len <= self.itemSize(0)) 0 else self.lowerBoundSize(data.len);

        while ((i < self.size()) and (self.itemSize(i) <= limit)) : (i += 1) {
            if(self.itemData(i).ptr == data.ptr) {
                return i;
            }
        }
        return null;
    }
    
    pub fn withdraw(self: *Self, n: usize) ?[]u8 {

        if ((self.size() == 0) or (n == 0)) {
            return null;
        }

        // Worst case guard -- if binary search finds that
        // element zero is a candidate, we'll search the
        // entire cache for direct O(N) performance.

        if (n <= self.itemSize(0)) {
            return self.scanForUnused(0, n);
        }

        // Check if cache can support size request.
        if (n > self.itemSize(self.size() - 1)) {
            return null;
        }

        // Begin scanning from first candidate index.
        return self.scanForUnused(self.lowerBoundSize(n), n);  
    }

    pub fn deposit(self: *Self, data: []u8) !void {

        if (data.len == 0) {
            return;
        }

        // Find lowest equal size index first...
        const idx = self.lowerBoundSize(data.len);

        const limit = data.len <<| 1;

        // From there, scan up the cache to see if
        // we have already encountered this pointer.
        // If so, set it to used and return.

        var i = idx;
        while ((i < self.size()) and (self.itemSize(i) <= limit)) : (i += 1) {
            if(self.itemData(i).ptr == data.ptr) {
                return self.setUsed(i, false);
            }
        }

        // insert is capcity checked -- add to cache
        try self.cache.insert(idx, .{ .data = data });
    }
};        

// Similar to the GeneralPurposeAllocator, the CachingAllocator
// will support bit alignment within [1, 2048]. Each step up
// in index will be equivalent to another power of two for
// alignment. So tabl[0] : align 1, table[3] : align 4...

// I'm making a distinction for a CPU allocator because
// other devices can use the caching allocator as well.

const CPUCachingAllocator = struct {

    const Self = @This();

    buffer: OrderedCache = OrderedCache.init(std.heap.page_allocator),

    backing_allocator: std.mem.Allocator = std.heap.page_allocator,

    // TODO: Create a dummy mutex that can be swapped via policy
    mutex: std.Thread.Mutex = std.Thread.Mutex{ },

    pub fn clear(self: *Self) void {
        self.buffer.clear(&self.backing_allocator);
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(&self.backing_allocator);
    }

    pub fn allocator(self: *Self) std.mem.Allocator {        
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    pub fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ret_addr: usize
    ) ?[*]u8 {        
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.mutex.lock();

        defer self.mutex.unlock();

        if(self.buffer.withdraw(len)) |data| {
            return data.ptr;
        }
        return self.backing_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
    }
    
    pub fn resize(
        ctx: *anyopaque,
        old_mem: []u8,
        log2_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.mutex.lock();

        defer self.mutex.unlock();

        // locate pointer in cache (if exists)
        if (self.buffer.locateMemory(old_mem)) |idx| {
            
            var data = self.buffer.cache.items[idx].data;

            if (self.backing_allocator.rawResize(data, log2_align, new_len, ret_addr)) {

                _ = self.buffer.cache.orderedRemove(idx);

                // The only reason this would fail is because
                // the buffer allocator couldn't resize the array.
                // We know, however, that the capacity of the array
                // is already large enough for this insertion.
                
                self.buffer.deposit(data) catch unreachable;

                return true;
            }
        }
        return false;
    }
     
    pub fn free(
        ctx: *anyopaque,
        old_mem: []u8,
        log2_align: u8,
        ret_addr: usize,
    ) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.mutex.lock();

        defer self.mutex.unlock();

        self.buffer.deposit(old_mem) catch {
            self.backing_allocator.rawFree(old_mem, log2_align, ret_addr);
        };
    }
};

/////////////////////////////////////////////////////////
/////// OrderedCache Testing Section ////////////////////

fn ensureWeakOrdering(buffer: *const OrderedCache) bool {    
    for(0..(buffer.size() - 1)) |i| {
        if(buffer.itemSize(i) > buffer.itemSize(i + 1)) {
            return false;
        }
    }
    return true;
}

test "OrderedCache: ensure weak-ordering" {
    
    const GPA = @import("std").heap.GeneralPurposeAllocator(.{});
    const rand = @import("std").rand;

    var gpa = GPA{};
    var allocator = gpa.allocator();
    var buffer = OrderedCache.init(allocator);
    var PCG = rand.Pcg.init(42);
    var pcg = PCG.random();


    defer {
        buffer.deinit(&allocator);   
        if (gpa.deinit() == .leak) { 
            @panic("LEAK DETECTED"); 
        }
    }

    // Create randomly sized allocations, deposit them
    // and then clear, rinse, repeat. Currently, this
    // is run 10 * (100 + 100) times, so 2000 items.

    for(0..10) |_| {
        // some repeat elements
        for(0..100) |_| {
            var n = pcg.int(usize) % 100;
            n = if(n == 0) 1 else n;
            try buffer.deposit(try allocator.alloc(u8, n));
        }
        try std.testing.expectEqual(buffer.size(), 100);
        try std.testing.expect(ensureWeakOrdering(&buffer));
        buffer.clear(&allocator);
        try std.testing.expectEqual(buffer.size(), 0);

        // many repeat elements
        for(0..100) |_| {
            var n = pcg.int(usize) % 10;
            n = if(n == 0) 1 else n;
            try buffer.deposit(try allocator.alloc(u8, n));
        }

        try std.testing.expectEqual(buffer.size(), 100);
        try std.testing.expect(ensureWeakOrdering(&buffer));
        buffer.clear(&allocator);
        try std.testing.expectEqual(buffer.size(), 0);
    }
}

test "OrderedCache: basic heuristic testing" {
    
    const GPA = @import("std").heap.GeneralPurposeAllocator(.{});

    var gpa = GPA{};
    var allocator = gpa.allocator();
    var buffer = OrderedCache.init(allocator);

    defer {
        buffer.deinit(&allocator);   
        if (gpa.deinit() == .leak) { 
            @panic("LEAK DETECTED"); 
        }
    }

    // Say you have items A, B, C.
    // 
    // A wants 100 bytes
    // 
    // B wants 300 bytes
    // 
    // Then both A and B surrender their memory… so we now have cached { 100, 300 }
    // 
    // Now let’s say that A is followed by C, so it’s asking for { 100, 100 }… but the cache only has { 100, 300 }
    // 
    // Now if B comes back and wants memory, it’ll ask for 300 bytes again. We’re empty so we have to allocate… now we have { 100, 300, 300 }.
    // 
    // Instead, if we forced C to allocate when it asked for 100 bytes and we were empty, we would end up with { 100, 100, 300 } which is ideal.
    // 
    // So the heuristic just has to make sure that the actual requests are as close to what ends up in the cache… something like:
    //
    //    optimize min: |sum(actual) - sum(cached)|

    const request1: usize = 100;
    const request2: usize = 300;
    const request3: usize = 100;

    {
    // allocate first two requests
    var a = try allocator.alloc(u8, request1);
    var b = try allocator.alloc(u8, request2);

    // deposit requests into cache (simulating free)
    try buffer.deposit(a);
    try buffer.deposit(b);
    }

    // cache now contains { 100, 300 }
    try std.testing.expectEqual(buffer.itemSize(0), 100);
    try std.testing.expectEqual(buffer.itemSize(1), 300);

    {
    // request memory { 100, 100, 300 }
    var a = buffer.withdraw(request1) orelse try allocator.alloc(u8, request1);
    var c = buffer.withdraw(request3) orelse try allocator.alloc(u8, request3);
    var b = buffer.withdraw(request2) orelse try allocator.alloc(u8, request2);

    // deposit requests into cache (simulating free)
    try buffer.deposit(a);
    try buffer.deposit(b);
    try buffer.deposit(c);
    }
    // cache should contain { 100, 100, 300 }
    try std.testing.expectEqual(buffer.itemSize(0), 100);
    try std.testing.expectEqual(buffer.itemSize(1), 100);
    try std.testing.expectEqual(buffer.itemSize(2), 300);
}

/////////////////////////////////////////////////////////
/////// CPUCachingAllocator Testing Section /////////////

test "CPUCachingAllocator: initialization" {

    const TypeA = struct {
        x: usize = 0      
    };

    var cpu_caching_allocator = CPUCachingAllocator{ };

    defer cpu_caching_allocator.deinit();

    var allocator = cpu_caching_allocator.allocator();

    var a = try allocator.alloc(TypeA, 10);

    allocator.free(a);

    try std.testing.expectEqual(cpu_caching_allocator.buffer.size(), 1);

}

test "CPUCachingAllocator: basic cache utilization" {

    const TypeA = struct {
        x: usize = 0      
    };

    var cpu_caching_allocator = CPUCachingAllocator{ };

    defer cpu_caching_allocator.deinit();

    var allocator = cpu_caching_allocator.allocator();

    var a = try allocator.alloc(TypeA, 10);

    var b = a;

    allocator.free(a);

    var c = try allocator.alloc(TypeA, 10);

    try std.testing.expect(b.ptr == c.ptr);
}

test "CPUCachingAllocator: alignment" {

    // TypeA will be aligned by usize, and TypeB
    // will be forced to go up rung in alignment

    const TypeA = struct {
        x: usize = 0      
    };
    const TypeB = struct {
        x: usize = 0,   
        y: bool = false
    };

    { 
        // ensure that log2 alignment is different...
        const align_a = std.math.ceilPowerOfTwoAssert(usize, @bitSizeOf(TypeA));
        const align_b = std.math.ceilPowerOfTwoAssert(usize, @bitSizeOf(TypeB));
        const log2_a = std.math.log2(align_a);
        const log2_b = std.math.log2(align_b);
        try std.testing.expect(log2_a < log2_b);
    }

    var cpu_caching_allocator = CPUCachingAllocator{ };

    defer cpu_caching_allocator.deinit();

    var allocator = cpu_caching_allocator.allocator();

    var a = try allocator.alloc(TypeA, 10);
    try std.testing.expectEqual(a.len, 10);

    allocator.free(a);

    var b = try allocator.alloc(TypeB, 4);
    try std.testing.expectEqual(b.len, 4);
    
    try std.testing.expect(@intFromPtr(a.ptr) == @intFromPtr(b.ptr));

    allocator.free(b);

    try std.testing.expectEqual(cpu_caching_allocator.buffer.size(), 1);

    // attempt to iterate through items

    for(b) |*item| {
        item.x = 0;
        item.y = false;
    }
}