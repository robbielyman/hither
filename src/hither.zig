const wordToFnMap = std.ComptimeStringMap([]const u8, .{
    .{ "add", "+" },
    .{ "subtract", "-" },
    .{ "multiply", "*" },
    .{ "divide", "/" },
    .{ "variable", "name" },
    .{ "call", "call" },
    .{ "assign", ":=" },
    .{ "lambdaEnd", "{" },
    .{ "lambda", "}" },
    .{ "macro", "$" },
    .{ "addrOf", "'" },
    .{ "ifEnd", "if" },
    .{ "elseEnd", "else" },
    .{ "then", "then" },
    .{ "tombstone", "break" },
    .{ "dupe", "dupe" },
    .{ "swap", "swap" },
    .{ "setTo", "top" },
    .{ "equal", "==" },
    .{ "whileFn", "while" },
    .{ "andFn", "and" },
    .{ "orFn", "or" },
    .{ "notFn", "not" },
    .{ "greater", ">" },
    .{ "greaterEq", ">=" },
    .{ "less", "<" },
    .{ "lessEq", "<=" },
    .{ "whileFn", "while" },
    .{ "noop", "_" },
    .{ "after", "," },
    .{ "dump", "dump" },
    .{ "print", "print" },
    .{ "modulo", "%" },
    .{ "join", "++" },
    .{ "heightIs", "height" },
});

const Hither = @This();

stack: Stack,
pad: *[pad_length]u8,
pad_idx: usize = 0,
msg: []const u8 = "",
lambda_idx: u16 = 0,
mode: enum { shallow, deep } = .deep,
writer: ?std.io.AnyWriter = null,

pub fn nextLambdaName(stack: *Stack, buffer: []u8) []const u8 {
    const hither: *Hither = @fieldParentPtr("stack", stack);
    const ret = std.fmt.bufPrint(buffer, "_lmb{x:0>4}", .{hither.lambda_idx}) catch unreachable;
    hither.lambda_idx += 1;
    return ret;
}

test "formatting" {
    var buf: [16]u8 = undefined;
    const ret = try std.fmt.bufPrint(&buf, "_lmb{x:0>4}", .{0});
    try std.testing.expectEqualStrings("_lmb0000", ret);
    const ret2 = try std.fmt.bufPrint(&buf, "_lmb{x:0>4}", .{0xdead});
    try std.testing.expectEqualStrings("_lmbdead", ret2);
}

pub fn init(buffer: []align(@alignOf(Cell)) u8) error{StackTooSmall}!Hither {
    var self: Hither = .{ .stack = Stack.init(buffer), .pad = undefined };

    const lib = @import("standard_library.zig");
    const info = @typeInfo(lib);
    inline for (info.Struct.decls) |decl| {
        const name = wordToFnMap.get(decl.name).?;
        const Fn = @field(lib, decl.name);
        const prev = self.stack.here;
        addAtHere(&self.stack, .{ .machine = Fn }) catch return error.StackTooSmall;
        addAtHere(&self.stack, .{ .addr = .{ .address = @intCast(prev -| 1) } }) catch return error.StackTooSmall;
        try addUtf8ToDictionary(&self.stack, name);
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
        self.msg = setMsgFmt(self, "read error: {s}", .{@errorName(err)});
        return .err;
    } orelse return .quit;
    defer self.pad_idx += input.len;
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

pub fn lookUpWord(stack: *Stack, token: []const u8) !Cell {
    const len = try std.math.divCeil(usize, token.len, 8);
    if (len > 255) return error.WordTooLong;
    var iterator = iterateDictionary(stack);
    while (iterator.next()) |entry| {
        if (len != entry.name_len) continue;
        if (!entry.match(stack, token)) continue;
        // std.debug.print("{}\n", .{stack.get(entry.address - (entry.name_len + 1))});
        return .{ .addr = .{ .address = entry.address - (entry.name_len + 1) } };
    }
    return error.NotFound;
}

const DictionaryIterator = struct {
    stack: *const Stack,
    current: ?Entry,

    fn next(self: *DictionaryIterator) ?Entry {
        const curr = self.current orelse return null;
        const ptr = curr.address - curr.name_len;
        const data = self.stack.get(ptr);
        if (data.addr.address == 0) {
            self.current = null;
            return curr;
        }
        // std.debug.print("next addr: 0x{x}\n", .{data.addr.address});
        const new_ptr = self.stack.get(data.addr.address);
        self.current = .{
            .name_len = new_ptr.len.length,
            .address = data.addr.address -| 1,
        };
        return curr;
    }

    const Entry = struct {
        name_len: u8,
        address: u32,

        fn match(self: Entry, stack: *const Stack, word: []const u8) bool {
            var idx: usize = 0;
            var name_ptr = self.address;
            while (idx < word.len) : (idx += 8) {
                const data = stack.get(name_ptr);
                const haystack: *const [8]u8 = @ptrCast(&data.utf8);
                const needle = word[idx..][0..@min(8, word[idx..].len)];
                const slice: []const u8 = if (std.mem.indexOfScalar(u8, haystack, 0)) |n| haystack[0..n] else haystack;
                if (!std.mem.eql(u8, slice, needle)) return false;
                name_ptr -= 1;
            }
            return true;
        }
    };
};

fn iterateDictionary(stack: *const Stack) DictionaryIterator {
    return .{ .stack = stack, .current = .{
        .name_len = stack.get(stack.here - 1).len.length,
        .address = @intCast(stack.here - 2),
    } };
}

pub const Result = enum { err, ok, quit, incomplete };

pub fn tick(self: *Hither) Result {
    const cell = (pop(&self.stack) catch |err| {
        switch (err) {
            error.BadArguments => self.msg = "bad arguments!",
            error.DivisionByZero => self.msg = "division by zero!",
            error.MathOverflow => self.msg = "math operation overflow!",
            error.StackOverflow => self.msg = "stack overflow!",
            error.NotSupported => self.msg = "operation not supported!",
            error.IOError => self.msg = "i/o error!",
        }
        return .err;
    }) orelse return .ok;
    switch (cell) {
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

fn setMessage(self: *Hither, cell: Cell) ![]const u8 {
    const slice = self.pad[self.pad_idx..];
    var stream = std.io.fixedBufferStream(slice);
    var writer = stream.writer();
    switch (cell) {
        .slice => return sliceFromSlice(self, cell) catch unreachable,
        else => try writer.print("{}", .{cell}),
    }
    self.pad_idx += stream.pos;
    return slice[0..stream.pos];
}

pub fn flush(self: *Hither) void {
    self.stack.stack_ptr = self.stack.capacity;
    self.msg = "";
    const old_pad = self.pad;
    self.pad = &self.stack.bytes[self.stack.here * 8 + pad ..][0..pad_length].*;
    std.mem.copyBackwards(u8, self.pad, old_pad);
}

pub fn addUtf8ToDictionary(stack: *Stack, utf8name: []const u8) error{StackTooSmall}!void {
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
    while (idx >= 8) {
        idx -= 8;
        const utf8: Cell = .{ .utf8 = @bitCast(utf8name[idx..][0..8].*) };
        addAtHere(stack, utf8) catch return error.StackTooSmall;
    }
    addAtHere(stack, len) catch return error.StackTooSmall;
}

pub fn addAtHere(stack: *Stack, cell: Cell) error{StackOverflow}!void {
    try roomAbove(stack, 1);
    stack.set(stack.here, cell);
    stack.here += 1;
}

// resolves according to stack.mode
pub fn pop(stack: *Stack) Error!?Cell {
    const hither: *Hither = @fieldParentPtr("stack", stack);
    defer hither.mode = .deep;
    if (stack.stack_ptr == stack.capacity) return null;
    var res = stack.get(stack.stack_ptr);
    // std.log.debug("popped {} in mode {s}", .{ res, @tagName(hither.mode) });
    stack.stack_ptr += 1;
    while (hither.mode == .deep) {
        switch (res) {
            .machine => |m| {
                try m(stack);
                if (stack.stack_ptr == stack.capacity) return null;
                res = stack.get(stack.stack_ptr);
                stack.stack_ptr += 1;
            },
            .addr => |a| {
                var addr = a.address;
                while (addr > 0) : (addr -= 1) {
                    const cell = stack.get(addr);
                    if (cell == .len) break;
                    try push(stack, cell);
                }
                if (stack.stack_ptr == stack.capacity) return null;
                res = stack.get(stack.stack_ptr);
                stack.stack_ptr += 1;
            },
            else => break,
        }
    }
    return res;
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
    // std.log.debug("pushed {}", .{cell});
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
