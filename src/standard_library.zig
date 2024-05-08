pub fn lambdaEnd(_: *Stack) Error!void {}

pub fn add(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = std.math.add(i64, a.integer, b.integer) catch {
            return error.MathOverflow;
        } },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            break :number .{ .number = float_a + float_b };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn subtract(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = std.math.sub(i64, b.integer, a.integer) catch {
            return error.MathOverflow;
        } },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            break :number .{ .number = float_b - float_a };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn multiply(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = std.math.mul(i64, a.integer, b.integer) catch {
            return error.MathOverflow;
        } },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            break :number .{ .number = float_a * float_b };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn divide(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = std.math.divTrunc(i64, b.integer, a.integer) catch |err| switch (err) {
            error.DivisionByZero => return error.DivisionByZero,
            error.Overflow => return error.MathOverflow,
        } },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            if (float_a == 0) return error.DivisionByZero;
            break :number .{ .number = float_b / float_a };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn assign(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 2)) return error.BadArguments;
    const hither: *h = @fieldParentPtr("stack", stack);
    hither.mode = .shallow;
    const lhs = (try h.pop(stack)).?;
    const rhs = (try h.pop(stack)) orelse return error.BadArguments;
    if (lhs != .addr) return error.BadArguments;
    stack.set(lhs.addr.address, rhs);
}

pub fn variable(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const name = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const value = (try h.pop(stack)) orelse return error.BadArguments;
    const hither: *h = @fieldParentPtr("stack", stack);
    const slice = try hither.sliceFromSlice(name);
    const utf8name = if (slice[0] == '\"' and slice[slice.len - 1] == '\"') slice[1 .. slice.len - 1] else slice;
    const prev = stack.here;
    try h.addAtHere(stack, value);
    errdefer stack.here = prev;
    try h.addAtHere(stack, .{ .addr = .{ .address = @intCast(prev - 1) } });
    h.addUtf8ToDictionary(stack, utf8name) catch return error.StackOverflow;
}

pub fn call(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const result = try h.pop(stack);
    if (result) |cell| try h.push(stack, cell);
}

pub fn lambda(stack: *Stack) Error!void {
    const here = stack.here;
    errdefer stack.here = here;
    var depth: usize = 1;
    const end = h.lookUpWord(stack, "{") catch unreachable;
    const start = h.lookUpWord(stack, "}") catch unreachable;
    const hither: *h = @fieldParentPtr("stack", stack);
    while (depth > 0) {
        if (!h.checkDepth(stack, 1)) return error.BadArguments;
        hither.mode = .shallow;
        const cell = (try h.pop(stack)) orelse return error.BadArguments;
        if (cell.eqlShallow(start)) depth += 1;
        if (cell.eqlShallow(end)) depth -= 1;
        if (depth != 0) try h.addAtHere(stack, cell);
    }
    var buf: [8]u8 = undefined;
    _ = h.nextLambdaName(stack, &buf);
    const addr = stack.here - 1;
    try h.addAtHere(stack, .{ .addr = .{ .address = @intCast(here - 1) } });
    h.addUtf8ToDictionary(stack, &buf) catch return error.StackOverflow;
    try h.push(stack, .{ .addr = .{ .address = @intCast(addr) } });
    hither.mode = .shallow;
}

pub fn macro(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const here = stack.here;
    errdefer stack.here = here;
    const hither: *h = @fieldParentPtr("stack", stack);
    while (h.checkDepth(stack, 1)) {
        hither.mode = .shallow;
        const cell = (try h.pop(stack)).?;
        try h.addAtHere(stack, cell);
    }
    var buf: [8]u8 = undefined;
    _ = h.nextLambdaName(stack, &buf);
    const addr = stack.here - 1;
    try h.addAtHere(stack, .{ .addr = .{ .address = @intCast(here - 1) } });
    h.addUtf8ToDictionary(stack, &buf) catch return error.StackOverflow;
    try h.push(stack, .{ .addr = .{ .address = @intCast(addr) } });
    hither.mode = .shallow;
}

pub fn addrOf(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const hither: *h = @fieldParentPtr("stack", stack);
    hither.mode = .shallow;
}

const h = @import("hither.zig");
const s = @import("stack.zig");
const Stack = s.Stack;
const Cell = s.Cell;
const Error = s.Error;
const Elem = Stack.Elem;
const std = @import("std");
