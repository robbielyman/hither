const Hither = @This();

stack: Stack,
pad: *[pad_length]u8,
pad_idx: usize = 0,
msg: []const u8 = "",

pub fn init(buffer: []align(@alignOf(Cell)) u8) error{StackTooSmall}!Hither {
    var self: Hither = .{ .stack = Stack.init(buffer), .pad = undefined };

    const lib = @import("standard_library.zig");
    const info = @typeInfo(lib);
    inline for (info.Struct.decls) |decl| {
        const name = wordToFnMap.get(decl.name).?;
        const Fn = @field(lib, decl.name);
        const prev = self.stack.here;
        addAtHere(&self.stack, .{ .machine = Fn }) catch return error.StackTooSmall;
        addAtHere(&self.stack, .{ .addr = .{ .address = @intCast(prev) } }) catch return error.StackTooSmall;
        try addNameToDictionary(&self.stack, name);
    }
    self.pad = &self.stack.bytes[self.stack.here * 8 + pad ..][0..pad_length].*;
    return self;
}

pub fn setMsgFmt(self: *Hither, comptime fmt: []const u8, args: anytype) []const u8 {
    const slice = self.pad[self.pad_idx..];
    var stream = std.io.fixedBufferStream(slice);
    var writer = stream.writer();
    writer.print(fmt, args) catch return "error while setting msg!";
    return slice[0..stream.pos];
}

pub fn parse(self: *Hither, stream: anytype) Result {
    const input = stream.readUntilDelimiterOrEof(self.pad[self.pad_idx..], '\n') catch |err| {
        if (err == error.EndOfStream) return .quit;
        self.msg = setMsgFmt(self, "parse error: {s}", .{@errorName(err)});
        return .err;
    } orelse return .quit;
    if (std.mem.startsWith(u8, input, "quit")) return .quit;
    var iterator = std.mem.tokenizeAny(u8, input, " \t\n\r()[]");
    while (iterator.next()) |token| {
        const cell = cellFromToken(self, token, iterator.index - token.len) catch |err| {
            self.msg = setMsgFmt(self, "parse error: {s}", .{@errorName(err)});
            return .err;
        };
        push(&self.stack, cell) catch {
            self.msg = "stack overflow!";
            return .err;
        };
    }
    return .ok;
}

fn cellFromToken(self: *Hither, token: []const u8, idx: usize) !Cell {
    int: {
        const ret: Cell = .{ .integer = std.fmt.parseInt(i64, token, 0) catch break :int };
        return ret;
    }
    float: {
        const ret: Cell = .{ .number = std.fmt.parseFloat(f64, token) catch break :float };
        return ret;
    }
    if (token[0] == '\"' and token[token.len - 1] == '\"') {
        const ret: Cell = .{
            .slice = .{ .address = @intCast(self.pad_idx + idx), .length = @intCast(token.len) },
        };
        return ret;
    }
    return try lookUpWord(&self.stack, token);
}

pub fn sliceFromSlice(self: *Hither, cell: Cell) Error![]const u8 {
    if (cell != .slice) return error.BadArguments;
    return self.pad[cell.slice.address..][0..cell.slice.length];
}

fn lookUpWord(stack: *Stack, token: []const u8) !Cell {
    const len = try std.math.divCeil(usize, token.len, 8);
    if (len > 255) return error.WordTooLong;
    var iterator = iterateDictionary(stack);
    while (iterator.next()) |entry| {
        if (len != entry.name_len) continue;
        if (!entry.match(token)) continue;
        return .{ .addr = .{ .address = entry.address - (entry.name_len + 2) } };
    }
    return error.NotFound;
}

const DictionaryIterator = struct {
    stack: *const Stack,
    current: ?Entry,

    fn next(self: *DictionaryIterator) ?Entry {
        const curr = self.current orelse return null;
        const ptr = curr.name_ptr - curr.name_len;
        const data: Cell = Stack.Elem.toCell(.addr, ptr[0]);
        if (data.addr.address == 0) {
            self.current = null;
            return curr;
        }
        const slice = self.stack.slice();
        const new_ptr: [*]Stack.Elem.Bare = slice.items(.data)[data.addr.address..].ptr;
        self.current = .{
            .name_len = Stack.Elem.toCell(.len, new_ptr[0]).len.length,
            .name_ptr = new_ptr - 1,
            .address = data.addr.address,
        };
        return curr;
    }

    const Entry = struct {
        name_len: u8,
        name_ptr: [*]Stack.Elem.Bare,
        address: u32,

        fn match(self: Entry, word: []const u8) bool {
            var idx: usize = 0;
            var name_ptr = self.name_ptr;
            while (idx < word.len) : (idx += 8) {
                const data = name_ptr[0].utf8;
                const haystack: *const [8]u8 = @ptrCast(&data);
                const needle = word[idx..][0..@min(8, word[idx..].len)];
                if (!std.mem.startsWith(u8, haystack, needle)) return false;
                name_ptr -= 1;
            }
            return true;
        }
    };
};

fn iterateDictionary(stack: *const Stack) DictionaryIterator {
    const slice = stack.*.slice().items(.data);
    return .{ .stack = stack, .current = .{
        .name_len = slice[stack.here].len.length,
        .name_ptr = slice[stack.here..].ptr - 1,
        .address = @intCast(stack.here),
    } };
}

pub const Result = enum { err, ok, quit, incomplete };

pub fn tick(self: *Hither) Result {
    while (self.stack.stack_ptr != self.stack.capacity) {
        const cell = pop(&self.stack).?;
        switch (cell) {
            .machine => |m| {
                m(&self.stack) catch |err| {
                    switch (err) {
                        error.BadArguments => self.msg = "bad arguments!",
                        error.DivisionByZero => self.msg = "division by zero!",
                        error.MathOverflow => self.msg = "math operation overflow!",
                        error.StackOverflow => self.msg = "stack overflow!",
                    }
                    return .err;
                };
            },
            .addr => |a| {
                var addr = a.address;
                while (addr > 0) : (addr -= 1) {
                    const c = self.stack.get(addr);
                    if (c == .len) break;
                    push(&self.stack, c) catch {
                        self.msg = "stack overflow!";
                        return .err;
                    };
                }
            },
            .len => {
                self.msg = "bad stack state!";
                return .err;
            },
            else => {
                if (self.stack.stack_ptr != self.stack.capacity) {
                    push(&self.stack, cell) catch unreachable;
                    return .incomplete;
                }
                self.msg = self.setMessage(cell) catch "unable to print!";
                return .ok;
            },
        }
    }
    return .ok;
}

fn setMessage(self: *Hither, cell: Cell) ![]const u8 {
    const slice = self.pad[self.pad_idx..];
    var stream = std.io.fixedBufferStream(slice);
    var writer = stream.writer();
    switch (cell) {
        .integer => |i| try writer.print("{d}", .{i}),
        .number => |f| try writer.print("{d}", .{f}),
        // FIXME: print the bytes instead
        .slice => return sliceFromSlice(self, cell) catch unreachable,
        .len => |l| try writer.print("{d}", .{l.length}),
        .utf8 => |u| try writer.print("{s}", .{&@as([8]u8, @bitCast(u))}),
        .addr => |a| try writer.print("addr: {d}", .{a.address}),
        .machine => |m| try writer.print("function: {d}", .{@intFromPtr(m)}),
    }
    return slice[0..stream.pos];
}

pub fn flush(self: *Hither) void {
    self.stack.stack_ptr = self.stack.capacity;
    self.pad_idx = 0;
    self.msg = "";
}

const wordToFnMap = std.ComptimeStringMap([]const u8, .{
    .{ "add", "+" },
    .{ "subtract", "-" },
    .{ "multiply", "*" },
    .{ "divide", "/" },
    .{ "variable", "name" },
    .{ "call", "call" },
    .{ "assign", "=" },
});

pub fn addNameToDictionary(stack: *Stack, utf8name: []const u8) error{StackTooSmall}!void {
    const block_len: u8 = @intCast(std.math.divCeil(usize, utf8name.len, 8) catch unreachable);
    const rem: u3 = @intCast(utf8name.len % 8);
    const len: Cell = .{ .len = .{ .length = block_len } };
    var idx = utf8name.len;
    if (rem > 0) {
        var utf8: [8]u8 = .{0} ** 8;
        @memcpy(utf8[0..rem], utf8name[utf8name.len - rem ..]);
        const last: Cell = .{ .utf8 = @bitCast(utf8) };
        addAtHere(stack, last) catch return error.StackTooSmall;
        idx -= rem;
    }
    while (idx > 8) : (idx -= 8) {
        const utf8: Cell = .{ .utf8 = @bitCast(utf8name[idx..][0..8].*) };
        addAtHere(stack, utf8) catch return error.StackTooSmall;
    }
    addAtHere(stack, len) catch return error.StackTooSmall;
}

pub fn addAtHere(stack: *Stack, cell: Cell) error{StackOverflow}!void {
    try roomAbove(stack, 1);
    stack.here += 1;
    stack.set(stack.here, cell);
}

pub fn pop(stack: *Stack) ?Cell {
    if (stack.stack_ptr == stack.capacity) return null;
    const res = stack.get(stack.stack_ptr);
    stack.stack_ptr += 1;
    return res;
}

pub fn resolve(stack: *Stack) Error!?Cell {
    while (true) {
        if (stack.stack_ptr == stack.capacity) return null;
        const res = stack.get(stack.stack_ptr);
        stack.stack_ptr += 1;
        switch (res) {
            .machine => |m| {
                try m(stack);
                continue;
            },
            .addr => |a| {
                var addr = a.address;
                while (addr > 0) : (addr -= 1) {
                    const cell = stack.get(addr);
                    if (cell == .len) break;
                    try push(stack, cell);
                }
                continue;
            },
            else => {},
        }
        return res;
    }
}

/// idx is an index into the stack portion of the stack.
/// positive indices count down from the top, with `0` being the top of the stack
/// negative indices count up from the bottom, with `-1` being the bottom
pub fn idxToOffset(stack: *const Stack, idx: i64) ?usize {
    const sign = idx >= 0;
    const offset: u32 = @abs(idx);
    const res = if (sign) stack.stack_ptr +| offset else stack.capacity -| offset;
    if (!(res >= stack.stack_ptr and res <= stack.capacity)) return null;
    return res;
}

pub fn typeAt(stack: *const Stack, idx: i64) ?Stack.Elem.Tag {
    const offset = idxToOffset(stack, idx) orelse return null;
    const slice = stack.slice();
    const types = slice.items(.tag);
    return types[offset];
}

pub fn push(stack: *Stack, cell: Cell) error{StackOverflow}!void {
    try roomAbove(stack, 1);
    stack.stack_ptr -= 1;
    stack.set(stack.stack_ptr, cell);
}

pub fn roomAbove(stack: *const Stack, num_elems: usize) error{StackOverflow}!void {
    if (stack.here + pad_length + pad + num_elems >= stack.stack_ptr) return error.StackOverflow;
}

pub fn checkDepth(stack: *const Stack, num_elems: usize) bool {
    return stack.stack_ptr + num_elems <= stack.capacity;
}

pub fn toNumber(cell: Cell) error{BadArguments}!f64 {
    if (!isArithmetic(cell)) return error.BadArguments;
    return switch (cell) {
        .integer => |i| @floatFromInt(i),
        .number => |f| f,
        else => unreachable,
    };
}

pub fn isArithmetic(t: Stack.Elem.Tag) bool {
    return switch (t) {
        .integer, .number => true,
        else => false,
    };
}

pub fn mathCoerce(t1: Stack.Elem.Tag, t2: Stack.Elem.Tag) error{BadArguments}!Stack.Elem.Tag {
    if (!(isArithmetic(t1) and isArithmetic(t2))) return error.BadArguments;
    return switch (t1) {
        .integer => if (t2 == .integer) .integer else .number,
        .number => .number,
        else => unreachable,
    };
}

const pad_length = 128 * 1024 * 8;
const pad = 1024 * 8;

const std = @import("std");
const s = @import("stack.zig");
const Stack = s.Stack;
pub const Cell = s.Cell;
const Error = s.Error;
