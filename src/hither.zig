const Hither = @This();

const Stack = std.MultiArrayList(Cell);
const Dictionary = std.StringArrayHashMapUnmanaged(Cell);

pub const Error = error{
    OutOfMemory,
    StackOverflow,
    BadArgument,
    ArithmeticOverflow,
    ZeroDenominator,
    PairMismatch,
    NotSupported,
    IOError,
    WordNotFound,
};

heap: Heap,
stack: Stack,
ret: Stack,
quotation_level: u1 = 0,
dictionary: Dictionary,
msg: []const u8 = "",
output: ?std.io.AnyWriter = null,

pub const Cell = struct {
    pub const Tag = enum(u2) {
        slice,
        integer,
        number,
        builtin,
    };

    tag: Tag,
    slice_is: enum(u2) {
        string,
        word,
        definition,
    } = .string,
    data: packed union {
        slice: packed struct {
            address: u32,
            length: u32,
        },
        integer: i64,
        number: f64,
        builtin: *const fn (*Hither) Error!void,
    },

    pub fn eqlShallow(a: Cell, b: Cell) bool {
        if (a.tag != b.tag) return false;
        return switch (a.tag) {
            .slice => a.data.slice.address == b.data.slice.address and a.data.slice.length == b.data.slice.length,
            .integer => a.data.integer == b.data.integer,
            .number => a.data.number == b.data.number,
            .builtin => @intFromPtr(a.data.builtin) == @intFromPtr(b.data.builtin),
        };
    }

    pub fn format(cell: Cell, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (cell.tag) {
            .slice => try writer.print("slice: address: 0x{x}, length: {d}, type: {s}", .{ cell.data.slice.address, cell.data.slice.length, @tagName(cell.slice_is) }),
            .integer => try writer.print("{d}", .{cell.data.integer}),
            .number => try writer.print("{d}", .{cell.data.number}),
            .builtin => try writer.print("function, address: 0x{x}", .{@intFromPtr(cell.data.builtin)}),
        }
    }

    test Cell {
        const a: Cell = .{
            .tag = .slice,
            .data = .{ .slice = .{ .address = 0xdeadbeef, .length = 0xfeedbacc } },
        };
        const b: Cell = .{
            .tag = .slice,
            .data = .{ .slice = .{ .address = 0xdeadbeef, .length = 0xfeedbacc } },
        };
        const c: Cell = .{
            .tag = .integer,
            .data = .{ .integer = @bitCast(@as(u64, 0xfeedbaccdeadbeef)) },
        };
        try std.testing.expectEqual(@as(i64, @bitCast(a.data.slice)), c.data.integer);
        try std.testing.expect(a.eqlShallow(b));
        try std.testing.expect(!a.eqlShallow(c));
    }
};

pub fn init(allocator: std.mem.Allocator, stack_size: usize, dictionary_size: usize, heap_size: u32) std.mem.Allocator.Error!Hither {
    var hither: Hither = .{
        .heap = try Heap.init(allocator, heap_size),
        .stack = .{},
        .ret = .{},
        .dictionary = try Dictionary.init(allocator, hither_lib.keys, hither_lib.vals),
    };
    try hither.stack.ensureUnusedCapacity(allocator, stack_size);
    try hither.ret.ensureUnusedCapacity(allocator, stack_size);
    try hither.dictionary.ensureUnusedCapacity(allocator, dictionary_size);
    return hither;
}

pub fn deinit(hither: *Hither, allocator: std.mem.Allocator) void {
    hither.stack.deinit(allocator);
    hither.ret.deinit(allocator);
    hither.dictionary.deinit(allocator);
    hither.heap.deinit(allocator);
    hither.* = undefined;
}

pub fn printStack(hither: *Hither, writer: std.io.AnyWriter) !void {
    while (hither.stack.popOrNull()) |cell| {
        switch (cell.tag) {
            .slice => {
                if (cell.slice_is != .definition) {
                    const bytes = hither.heap.fromAddress(cell.data.slice.address).?;
                    try writer.writeAll(bytes[0..cell.data.slice.length]);
                    try writer.writeAll("\n");
                } else try writer.print("{}\n", .{cell});
            },
            else => try writer.print("{}\n", .{cell}),
        }
    }
}

pub fn dumpState(hither: *Hither, writer: std.io.AnyWriter) !void {
    try writer.writeAll("---------------\n");
    try writer.writeAll("RETURN STACK:\n");
    for (0..hither.ret.len) |i| {
        try writer.print("{any}\n", .{hither.ret.get(hither.ret.len - 1 - i)});
    }
    try writer.writeAll("STACK:\n");
    for (0..hither.stack.len) |i| {
        try writer.print("{any}\n", .{hither.stack.get(hither.stack.len - 1 - i)});
    }
    try writer.writeAll("---------------\n");
}

pub const Result = enum { ok, err, incomplete, quit };

pub fn parse(hither: *Hither, input: std.io.AnyReader, output: std.io.AnyWriter) Result {
    hither.output = output;
    const allocator = hither.heap.allocator();
    const line = input.readUntilDelimiterOrEofAlloc(allocator, '\n', 2048) catch |err| {
        if (err == error.StreamTooLong) hither.msg = "input line too long! max size is 2048 bytes";
        hither.msg = std.fmt.allocPrint(allocator, "read error: {s}", .{@errorName(err)}) catch "out of memory while printing error message!";
        return .err;
    } orelse return .quit;
    if (std.mem.eql(u8, line, "quit")) return .quit;
    var iterator = std.mem.tokenizeAny(u8, line, "\r\n\t ");
    while (iterator.next()) |token| {
        const cell: Cell = cell: {
            int: {
                const int = std.fmt.parseInt(i64, token, 0) catch break :int;
                break :cell .{ .tag = .integer, .data = .{ .integer = int } };
            }
            number: {
                const number = std.fmt.parseFloat(f64, token) catch break :number;
                break :cell .{ .tag = .number, .data = .{ .number = number } };
            }
            slice: {
                if (token[0] != '\"') break :slice;
                const addr = hither.heap.addressOf(token.ptr + 1) catch unreachable;
                if (token.len > 1 and token[token.len - 1] == '\"') {
                    break :cell .{
                        .tag = .slice,
                        .data = .{
                            .slice = .{ .address = addr, .length = @intCast(token.len - 2) },
                        },
                    };
                }
                const start = (iterator.index + 1) - token.len;
                while (iterator.next()) |next| {
                    if (next[next.len - 1] == '\"') {
                        break :cell .{
                            .tag = .slice,
                            .data = .{
                                .slice = .{ .address = addr, .length = @intCast(iterator.index - (start + 1)) },
                            },
                        };
                    }
                }
                hither.msg = "parse error: unterminated string!";
                return .err;
            }
            const addr = hither.heap.addressOf(token.ptr) catch unreachable;
            break :cell .{
                .tag = .slice,
                .slice_is = .word,
                .data = .{
                    .slice = .{ .address = addr, .length = @intCast(token.len) },
                },
            };
        };
        hither.push(cell) catch |err| {
            hither.msg = switch (err) {
                error.OutOfMemory => "error: out of memory!",
                error.ArithmeticOverflow => "error: arithmetic overflow!",
                error.BadArgument => "error: bad argument!",
                error.StackOverflow => "error: stack overflow!",
                error.ZeroDenominator => "error: zero in denominator!",
                error.PairMismatch => "error: closing word found without matching opening word!",
                error.NotSupported => "error: that operation is not supported!",
                error.IOError => "error while performing I/O!",
                error.WordNotFound => "error: no definition found for word!",
            };
            return .err;
        };
    }
    return if (hither.ret.len != 0) .incomplete else .ok;
}

pub fn flush(hither: *Hither) void {
    hither.msg = "";
    hither.stack.len = 0;
    hither.ret.len = 0;
    hither.markAndSweep();
}

pub fn push(hither: *Hither, cell: Cell) Error!void {
    switch (cell.tag) {
        .builtin => {
            if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
            hither.ret.appendAssumeCapacity(cell);
            try @call(.auto, cell.data.builtin, .{hither});
        },
        .slice => {
            switch (cell.slice_is) {
                .string => {
                    if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
                    hither.stack.appendAssumeCapacity(cell);
                },
                .definition => {
                    if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
                    hither.ret.appendAssumeCapacity(cell);
                    try hither_lib.iterateThrough(hither);
                },
                .word => {
                    if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
                    hither.ret.appendAssumeCapacity(cell);
                    try hither_lib.lookUpWord(hither);
                },
            }
        },
        else => {
            if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
            hither.stack.appendAssumeCapacity(cell);
        },
    }
}

pub fn popReturn(hither: *Hither) ?Cell {
    return hither.ret.popOrNull();
}

pub fn pop(hither: *Hither) ?Cell {
    return hither.stack.popOrNull();
}

fn tagContainingHeader(hither: *Hither, cell: Cell) void {
    switch (cell.tag) {
        .slice => {
            const header = hither.heap.containingInUseHeader(cell.data.slice.address) orelse return;
            // attempt to short-circuit recursive tagging
            if (Heap.Header.isPtrTagged(header.next)) return;
            header.tag();
            if (cell.slice_is != .definition) return;
            const ptr = hither.heap.fromAddress(cell.data.slice.address) orelse return;
            const cells: [*]Cell = @ptrCast(@alignCast(ptr));
            for (cells[0..cell.data.slice.length]) |c| hither.tagContainingHeader(c);
        },
        else => {},
    }
}

fn markAndSweep(hither: *Hither) void {
    // mark
    for (hither.dictionary.keys()) |key| {
        const addr = hither.heap.addressOf(key.ptr) catch continue;
        const header = hither.heap.containingInUseHeader(addr) orelse continue;
        header.tag();
    }
    for (hither.dictionary.values()) |cell| hither.tagContainingHeader(cell);
    // sweep
    var used = hither.heap.used;
    while (used) |ptr| {
        used = Heap.Header.unTagPtr(ptr.next);
        if (Heap.Header.isPtrTagged(ptr.next)) continue;
        hither.heap.discard(ptr);
    }
    used = hither.heap.used;
    while (used) |ptr| : (used = ptr.next) {
        ptr.next = Heap.Header.unTagPtr(ptr.next);
    }
}

test "ref" {
    _ = Hither;
    _ = Cell;
    _ = Heap;
    _ = hither_lib;
}

const std = @import("std");
const Heap = @import("heap.zig");
const hither_lib = @import("hither_lib.zig");
