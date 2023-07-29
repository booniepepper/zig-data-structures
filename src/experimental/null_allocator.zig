// The NullAllocator is meant to be used as a fallback
// for allocator composition.

// For example, a StackAllocator, if it runs out of memory,
// can dispatch to another allocator to fulfill the request.
// If we want that to signal an error, we can give it the
// NullAllocator as a fallback and that will signal an
// "OutOfMemory" error, enforcing that we don't ask for
// more memory than is on the stack.


const std = @import("std");

const Self = @This();

pub fn allocator() std.mem.Allocator {        
    return .{
        .ptr = undefined,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .free = free,
        },
    };
}

fn alloc(
    ctx: *anyopaque,
    len: usize,
    log2_ptr_align: u8,
    ret_addr: usize
) ?[*]u8 {
    _ = ret_addr;
    _ = log2_ptr_align;
    _ = len;
    _ = ctx;        
    return null;
}
        
fn resize(
    ctx: *anyopaque,
    old_mem: []u8,
    log2_align: u8,
    new_len: usize,
    ret_addr: usize,
) bool {
    _ = ret_addr;
    _ = new_len;
    _ = log2_align;
    _ = old_mem;
    _ = ctx;
    return false;
}
         
fn free(
    ctx: *anyopaque,
    old_mem: []u8,
    log2_align: u8,
    ret_addr: usize,
) void {
    _ = ret_addr;
    _ = log2_align;
    _ = old_mem;
    _ = ctx;
}
