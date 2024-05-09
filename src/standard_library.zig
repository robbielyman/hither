pub fn lambdaEnd(_: *Stack) Error!void {}

pub fn ifEnd(_: *Stack) Error!void {}

pub fn elseEnd(_: *Stack) Error!void {}

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

pub fn andFn(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const data: Cell = .{ .integer = if (a.eqlShallow(.{ .integer = 0 }) or b.eqlShallow(.{ .integer = 0 })) 0 else 1 };
    try h.push(stack, data);
}

pub fn notFn(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    const data: Cell = .{ .integer = if (a.eqlShallow(.{ .integer = 0 })) 1 else 0 };
    try h.push(stack, data);
}

pub fn orFn(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const data: Cell = .{ .integer = if (a.eqlShallow(.{ .integer = 0 }) and b.eqlShallow(.{ .integer = 0 })) 0 else 1 };
    try h.push(stack, data);
}

pub fn greater(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = if (a.integer > b.integer) 1 else 0 },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number .{ .integer = 0 };
            break :number .{ .integer = if (float_a > float_b) 1 else 0 };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn after(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 2)) return error.BadArguments;
    const top = stack.get(stack.stack_ptr);
    stack.stack_ptr += 1;
    const res = try h.pop(stack);
    if (res) |cell| try h.push(stack, cell);
    try h.push(stack, top);
}

pub fn dump(stack: *Stack) Error!void {
    const hither: *h = @fieldParentPtr("stack", stack);
    const slice = hither.pad[hither.pad_idx..];
    var stream = std.io.fixedBufferStream(slice);
    var writer = stream.writer();
    writer.print("STACK DUMP:\n", .{}) catch {
        stack.stack_ptr = stack.capacity;
        return;
    };
    var idx: usize = 0;
    while (stack.stack_ptr < stack.capacity) : (stack.stack_ptr += 1) {
        writer.print("index {d}: {t}\n", .{ idx, stack.get(stack.stack_ptr) }) catch {
            stack.stack_ptr = stack.capacity;
            return;
        };
        idx += 1;
    }
    writer.print("STACK DUMP END", .{}) catch {
        stack.stack_ptr = stack.capacity;
        return;
    };
    try h.push(stack, .{ .slice = .{
        .address = @intCast(hither.pad_idx),
        .length = @intCast(stream.pos),
    } });
    hither.pad_idx += stream.pos;
}

pub fn less(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = if (a.integer < b.integer) 1 else 0 },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number .{ .integer = 0 };
            break :number .{ .integer = if (float_a < float_b) 1 else 0 };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn lessEq(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = if (a.integer <= b.integer) 1 else 0 },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number .{ .integer = 1 };
            break :number .{ .integer = if (float_a < float_b) 1 else 0 };
        },
        else => unreachable,
    };
    try h.push(stack, data);
}

pub fn greaterEq(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    const res_type = try h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags);
    const data: Cell = switch (res_type) {
        .integer => .{ .integer = if (a.integer >= b.integer) 1 else 0 },
        .number => number: {
            const float_a = h.toNumber(a) catch unreachable;
            const float_b = h.toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number .{ .integer = 1 };
            break :number .{ .integer = if (float_a < float_b) 1 else 0 };
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

pub fn dupe(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const cell = (try h.pop(stack)) orelse return error.BadArguments;
    try h.push(stack, cell);
    try h.push(stack, cell);
}

pub fn swap(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    try h.push(stack, a);
    try h.push(stack, b);
}

pub fn setTo(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const cell = try h.pop(stack) orelse return error.BadArguments;
    if (cell != .integer) return error.BadArguments;
    const height: usize = if (cell.integer < 0) 0 else @intCast(cell.integer);
    while (stack.stack_ptr > stack.capacity - height) {
        try h.push(stack, .{ .integer = 0 });
    } else stack.stack_ptr = stack.capacity - height;
}

pub fn then(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const brk = h.lookUpWord(stack, "break") catch unreachable;
    _ = brk; // autofix
    const else_loc: ?usize, const if_loc: usize = tunnel: {
        const if_cell = h.lookUpWord(stack, "if") catch unreachable;
        const else_cell = h.lookUpWord(stack, "else") catch unreachable;
        const then_cell = h.lookUpWord(stack, "then") catch unreachable;
        var ptr = stack.stack_ptr;
        var else_loc: ?usize = null;
        var depth: usize = 1;
        while (ptr < stack.capacity and depth > 0) : (ptr += 1) {
            const cell = stack.get(ptr);
            if (cell.eqlShallow(then_cell)) depth += 1;
            if (cell.eqlShallow(else_cell) and depth == 1) else_loc = ptr;
            if (cell.eqlShallow(if_cell)) {
                depth -= 1;
                if (depth == 0) break :tunnel .{ else_loc, ptr };
            }
        } else return error.BadArguments;
    };
    const top = stack.stack_ptr;
    if (if_loc == stack.capacity) return error.BadArguments;
    stack.stack_ptr = if_loc + 1;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const cell = (try h.pop(stack)) orelse return error.BadArguments;
    if (!cell.eqlShallow(.{ .integer = 0 })) {
        var other = stack.stack_ptr - 1;
        const limit = if (else_loc) |loc| loc else top;
        stack.stack_ptr = if_loc - 1;
        while (stack.stack_ptr >= limit) {
            stack.set(other, stack.get(stack.stack_ptr));
            stack.stack_ptr -= 1;
            other -= 1;
        }
        stack.stack_ptr = other + 1;
    } else if (else_loc) |loc| {
        var other = stack.stack_ptr - 1;
        stack.stack_ptr = loc - 1;
        while (stack.stack_ptr >= top) {
            stack.set(other, stack.get(stack.stack_ptr));
            stack.stack_ptr -= 1;
            other -= 1;
        }
        stack.stack_ptr = other + 1;
    }
}

pub fn tombstone(stack: *Stack) Error!void {
    stack.stack_ptr = stack.capacity;
}

pub fn equal(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const a = (try h.pop(stack)) orelse return error.BadArguments;
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    const b = (try h.pop(stack)) orelse return error.BadArguments;
    const res: Cell = res: {
        if (!(std.meta.activeTag(a) == std.meta.activeTag(b))) {
            _ = h.mathCoerce(Elem.fromCell(a).tags, Elem.fromCell(b).tags) catch break :res .{ .integer = 0 };
            const float_a: f64 = switch (a) {
                .integer => |i| @floatFromInt(i),
                .number => |f| f,
                else => unreachable,
            };
            const float_b: f64 = switch (b) {
                .integer => |i| @floatFromInt(i),
                .number => |f| f,
                else => unreachable,
            };
            break :res .{
                .integer = if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) 1 else 0,
            };
        }
        if (a.eqlShallow(b)) break :res .{ .integer = 1 };
        switch (a) {
            .slice => {
                const hither: *h = @fieldParentPtr("stack", stack);
                const slice_a = hither.sliceFromSlice(a) catch unreachable;
                const slice_b = hither.sliceFromSlice(b) catch unreachable;
                break :res .{ .integer = if (std.mem.eql(u8, slice_a, slice_b)) 1 else 0 };
            },
            else => {},
        }
        break :res .{ .integer = 0 };
    };
    try h.push(stack, res);
}

pub fn whileFn(stack: *Stack) Error!void {
    if (!h.checkDepth(stack, 1)) return error.BadArguments;
    var cond = (try h.pop(stack)) orelse return error.BadArguments;
    while (!cond.eqlShallow(.{ .integer = 0 })) {
        if (!h.checkDepth(stack, 1)) return error.BadArguments;
        try dupe(stack);
        const duped = stack.stack_ptr;
        stack.stack_ptr += 1;
        cond = (try h.pop(stack)) orelse return error.BadArguments;
        if (!cond.eqlShallow(.{ .integer = 0 })) {
            stack.set(stack.stack_ptr, stack.get(duped));
        }
    }
}

pub fn noop(_: *Stack) Error!void {}

const h = @import("hither.zig");
const s = @import("stack.zig");
const Stack = s.Stack;
const Cell = s.Cell;
const Error = s.Error;
const Elem = Stack.Elem;
const std = @import("std");
