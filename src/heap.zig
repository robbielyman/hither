const Heap = @This();

used: ?*Header,
free: ?*Header,
buf: [*]align(@sizeOf(Header)) u8,
capacity_in_headers: usize,

pub const Header = struct {
    size_in_headers: u32,
    used_size_in_bytes: u32,
    next: ?*Header,

    fn precedes(a: *Header, b: ?*Header) bool {
        return @intFromPtr(a) < @intFromPtr(b);
    }

    fn eql(a: *Header, b: ?*Header) bool {
        return @intFromPtr(a) == @intFromPtr(b);
    }

    comptime {
        std.debug.assert(@alignOf(Header) < @sizeOf(Header));
    }

    pub fn tag(header: *Header) void {
        if (isPtrTagged(header.next)) return;
        header.next = @ptrFromInt(@intFromPtr(header.next) + @alignOf(Header));
    }

    pub fn isPtrTagged(header: ?*Header) bool {
        return @intFromPtr(header) % @sizeOf(Header) != 0;
    }

    pub fn unTagPtr(header: ?*Header) ?*Header {
        const ptr_int = @intFromPtr(header);
        return @ptrFromInt(ptr_int - (ptr_int % @sizeOf(Header)));
    }
};

pub fn fromAddress(self: Heap, address: u32) ?[*]u8 {
    if (@as(usize, address) > @sizeOf(Header) * self.capacity_in_headers) return null;
    return self.buf + address;
}

pub fn addressOf(self: Heap, ptr: *const anyopaque) error{NotInHeap}!u32 {
    const location = std.math.sub(usize, @intFromPtr(ptr), @intFromPtr(self.buf)) catch return error.NotInHeap;
    if (location > @sizeOf(Header) * self.capacity_in_headers) return error.NotInHeap;
    return std.math.cast(u32, location) orelse return error.NotInHeap;
}

pub fn containingInUseHeader(self: Heap, address: u32) ?*Header {
    if (address > @sizeOf(Header) * self.capacity_in_headers) return null;
    const ptr = @intFromPtr(self.buf) + address;
    var used = self.used;
    while (used) |header| : (used = Header.unTagPtr(header.next)) {
        if (ptr > @intFromPtr(header) and ptr < @intFromPtr(header) + @sizeOf(Header) + header.used_size_in_bytes) return header;
    }
    return null;
}

/// allocates a heap using `backing_allocator` with capacity `capacity` bytes.
pub fn init(backing_allocator: std.mem.Allocator, capacity: u32) std.mem.Allocator.Error!Heap {
    const capacity_in_headers = @divFloor(capacity, @sizeOf(Header));
    const buf = try backing_allocator.alignedAlloc(Header, @sizeOf(Header), capacity_in_headers);
    buf[0] = .{
        .size_in_headers = capacity_in_headers,
        .used_size_in_bytes = 0,
        .next = null,
    };
    return .{
        .used = null,
        .free = &buf[0],
        .buf = @ptrCast(buf.ptr),
        .capacity_in_headers = capacity_in_headers,
    };
}

/// destroys a heap created with `backing_allocator`.
pub fn deinit(self: *Heap, backing_allocator: std.mem.Allocator) void {
    const buf: [*]align(@sizeOf(Header)) Header = @ptrCast(self.buf);
    backing_allocator.free(buf[0..self.capacity_in_headers]);
    self.* = undefined;
}

/// returns the type-erased allocator
pub fn allocator(self: *Heap) std.mem.Allocator {
    return .{ .ptr = self, .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    } };
}

pub fn discard(self: *Heap, header: *Header) void {
    var used = self.used;
    while (used) |ptr| : (used = Header.unTagPtr(ptr.next)) {
        if (ptr.eql(header)) {
            const headers_ptr: [*]Header = @ptrCast(header);
            const buf_ptr: [*]u8 = @ptrCast(headers_ptr + 1);
            free(self, buf_ptr[0..header.used_size_in_bytes], 0, 0);
        }
    }
}

fn free(ctx: *anyopaque, buf: []u8, _: u8, _: usize) void {
    const self: *Heap = @ptrCast(@alignCast(ctx));
    const location_in_bytes = @intFromPtr(buf.ptr) - @intFromPtr(self.buf); // asserts that buf belongs to the heap
    const idx: usize = @divExact(location_in_bytes, @sizeOf(Header)); // asserts that buf is Header-aligned
    const buf_len: u32 = @intCast(buf.len); // asserts that buf.len is only a u32
    const header_ptr: [*]Header = @ptrCast(self.buf);
    const header = &header_ptr[idx - 1]; // asserts that buf is not the first header
    std.debug.assert(idx - 1 + header.size_in_headers <= self.capacity_in_headers);
    if (buf_len != header.used_size_in_bytes) std.debug.panic(
        "allocated size {d} does not match free size {d}!",
        .{ header.used_size_in_bytes, buf_len },
    );
    header.used_size_in_bytes = 0;

    // remove from the used list
    blk: {
        var used = self.used orelse break :blk;
        if (used.eql(header)) {
            self.used = Header.unTagPtr(header.next);
            header.next = null;
            break :blk;
        }
        while (Header.unTagPtr(used.next)) |next| : (used = next) {
            if (next.eql(header)) {
                used.next = Header.unTagPtr(header.next);
                header.next = null;
                break :blk;
            }
        }
    }

    if (header.precedes(self.free)) {
        // coalesce chunks: the lhs is the location after the end of the block described by header
        if (@intFromPtr(header) + (@sizeOf(Header) * header.size_in_headers) == @intFromPtr(self.free)) {
            header.size_in_headers += self.free.?.size_in_headers;
            header.next = self.free.?.next;
        } else header.next = self.free;
        self.free = header;
        return;
    }
    var prev = self.free orelse {
        self.free = header;
        header.next = null;
        return;
    };
    while (prev.precedes(header)) {
        if (header.precedes(prev.next)) break;
        const next = prev.next orelse break;
        std.debug.assert(prev.precedes(next)); // asserts the free list is in order
        prev = next;
    }

    // coalesce chunks: the lhs is the location after the end of the block described by header
    if (@intFromPtr(header) + (@sizeOf(Header) * header.size_in_headers) == @intFromPtr(prev.next)) {
        header.size_in_headers += prev.next.?.size_in_headers;
        header.next = prev.next.?.next;
    } else header.next = prev.next;
    // coalesce chunks: the lhs is the location after the end of the block described by prev
    if (@intFromPtr(prev) + (@sizeOf(Header) * @as(usize, prev.size_in_headers)) == @intFromPtr(header)) {
        prev.size_in_headers += header.size_in_headers;
        prev.next = header.next;
    } else prev.next = header;
}

fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
    // we're simply not allocating things that need greater alignment, so this is fine
    const alignment: std.mem.Allocator.Log2Align = @intCast(ptr_align);
    if (@as(usize, 1) << alignment > @alignOf(Header)) return null;
    const self: *Heap = @ptrCast(@alignCast(ctx));
    const len_in_bytes = std.math.cast(u32, len) orelse return null;
    // this is the minimum number of header-sized blocks needed to accommodate len bytes and a header;
    // on overflow, we just return null.
    const size_in_headers: u32 = std.math.add(u32, @divFloor(
        std.math.cast(
            u32,
            (std.math.add(usize, len, @sizeOf(Header)) catch
                return null) - 1,
        ) orelse return null,
        @sizeOf(Header),
    ), 1) catch return null;

    // find a chunk that fits
    const header = header: {
        var prev = self.free orelse return null;
        // the first chunk fits
        if (prev.size_in_headers >= size_in_headers) {
            // exact fit
            if (prev.size_in_headers == size_in_headers) {
                prev.used_size_in_bytes = len_in_bytes;
                self.free = prev.next;
                break :header prev;
            } else {
                const headers_ptr: [*]Header = @ptrCast(prev);
                prev.size_in_headers -= size_in_headers;
                prev = &(headers_ptr + prev.size_in_headers)[0];
                prev.size_in_headers = size_in_headers;
                prev.used_size_in_bytes = len_in_bytes;
                break :header prev;
            }
        }
        while (prev.next) |next| : (prev = next) {
            if (next.size_in_headers >= size_in_headers) {
                // exact fit
                if (next.size_in_headers == size_in_headers) {
                    next.used_size_in_bytes = len_in_bytes;
                    prev.next = next.next;
                    break :header next;
                } else {
                    const headers_ptr: [*]Header = @ptrCast(next);
                    next.size_in_headers -= size_in_headers;
                    var ret = &(headers_ptr + next.size_in_headers)[0];
                    ret.size_in_headers = size_in_headers;
                    ret.used_size_in_bytes = len_in_bytes;
                    break :header ret;
                }
            }
        }
        return null;
    };

    // add to the used list
    header.next = self.used;
    self.used = header;
    const headers_ptr: [*]Header = @ptrCast(header);
    return @ptrCast(headers_ptr + 1);
}

fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, _: usize) bool {
    const alignment: std.mem.Allocator.Log2Align = @intCast(buf_align);
    std.debug.assert(@intFromPtr(buf.ptr) % (@as(usize, 1) << alignment) == 0);
    if (new_len > buf.len) return false;
    const self: *Heap = @ptrCast(@alignCast(ctx));
    const location_in_bytes = @intFromPtr(buf.ptr) - @intFromPtr(self.buf); // asserts that buf belongs to the heap
    const idx: usize = @divExact(location_in_bytes, @sizeOf(Header)); // asserts that buf is Header-aligned
    const len: u32 = @intCast(new_len); // asserts that buf.len is only a u32
    const header_ptr: [*]Header = @ptrCast(self.buf);
    const header = &header_ptr[idx - 1]; // asserts that buf is not the first header
    header.used_size_in_bytes = len;
    return true;
}

test "basic usage" {
    var heap = try Heap.init(std.testing.allocator, 0xbeef);
    try std.testing.expect(heap.used == null);
    defer heap.deinit(std.testing.allocator);
    const ally = heap.allocator();
    {
        const string = try ally.dupe(u8, "this is a test string!");
        defer ally.free(string);
        try std.testing.expect(heap.used != null);
        const slice = try ally.alloc(usize, 200);
        @memset(slice, 0xdeadbeef);
        defer ally.free(slice);
        const addr = try heap.addressOf(slice.ptr);
        try std.testing.expect(heap.containingInUseHeader(addr) != null);
    }
    try std.testing.expect(heap.used == null);
}

const std = @import("std");
