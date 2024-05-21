pub const keys = constructKeysVals(.keys);
pub const vals = constructKeysVals(.vals);

fn constructKeysVals(comptime which: enum { keys, vals }) switch (which) {
    .keys => []const []const u8,
    .vals => []const Cell,
} {
    const map = [_][2][]const u8{
        .{ "+", "add" },
        .{ "-", "subtract" },
        .{ "*", "multiply" },
        .{ "/", "divide" },
        .{ "%", "modulo" },
        .{ ">", "greater" },
        .{ ">=", "greaterEq" },
        .{ "<", "less" },
        .{ "<=", "lessEq" },
        .{ "==", "equal" },
        .{ "dupe", "dupe" },
        .{ "swap", "swap" },
        .{ "height", "heightIs" },
        .{ "top", "setTo" },
        .{ "drop", "drop" },
        .{ "and", "andFn" },
        .{ "or", "orFn" },
        .{ "not", "notFn" },
        .{ "print", "print" },
        .{ "++", "join" },
        .{ ":=", "variable" },
        .{ "@", "call" },
        .{ "while", "whileFn" },
        .{ "_", "noop" },
        .{ "'", "xt" },
        .{ "{", "lambdaStart" },
        .{ "}", "lambdaEnd" },
        .{ "if", "ifStart" },
        .{ "else", "elseStart" },
        .{ "then", "then" },
        .{ "exit", "exit" },
        .{ "dump", "dumpState" },
        .{ "inspect", "inspect" },
        .{ "abort", "breakFn" },
    };
    return switch (which) {
        .keys => comptime blk: {
            var ret: [map.len][]const u8 = undefined;
            for (map, 0..) |pair, i| {
                ret[i] = pair[0];
            }
            const keys_list = ret;
            break :blk &keys_list;
        },
        .vals => comptime blk: {
            var ret: [map.len]Cell = undefined;
            for (map, 0..) |pair, i| {
                ret[i] = .{
                    .tag = .builtin,
                    .data = .{ .builtin = @field(@This(), pair[1]) },
                };
            }
            const vals_list = ret;
            break :blk &vals_list;
        },
    };
}

/// most functions in this file should begin with the line `if (try preamble(hither)) return;`
fn preamble(hither: *Hither) Error!bool {
    // pops the function which was just pushed onto the return stack
    const this = hither.ret.pop();
    if (isXt(hither) or isDeferred(hither)) {
        if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
        hither.stack.appendAssumeCapacity(this);
        return true;
    }
    return false;
}

/// returns true if the value on top of the stack is a deferred-execution builtin
/// e.g. (`if`, `else`, the opening of a `{` `}` pair, and so on)
fn isDeferred(hither: *Hither) bool {
    const this = hither.ret.popOrNull() orelse return false;
    defer hither.ret.appendAssumeCapacity(this);
    const deferred_builtins = [_][]const u8{
        "lambdaStart",
        "ifStart",
        "elseStart",
    };
    inline for (deferred_builtins) |name| {
        const cell: Cell = .{
            .tag = .builtin,
            .data = .{ .builtin = @field(@This(), name) },
        };
        if (this.eqlShallow(cell)) return true;
    }
    return false;
}

/// returns true if the value on top of the return stack is xt, and pops it if so
fn isXt(hither: *Hither) bool {
    const this = hither.ret.popOrNull() orelse return false;
    const xt_cell: Cell = .{
        .tag = .builtin,
        .data = .{ .builtin = xt },
    };
    if (this.eqlShallow(xt_cell)) return true;
    // it wasn't xt; put it back
    hither.ret.appendAssumeCapacity(this);
    return false;
}

fn arithmeticCoerce(a: Cell.Tag, b: Cell.Tag) error{BadArgument}!Cell.Tag {
    return switch (a) {
        .integer => switch (b) {
            .integer => .integer,
            .number => .number,
            else => error.BadArgument,
        },
        .number => switch (b) {
            .integer, .number => .number,
            else => error.BadArgument,
        },
        else => error.BadArgument,
    };
}

fn toNumber(cell: Cell) error{BadArgument}!f64 {
    return switch (cell.tag) {
        .integer => @floatFromInt(cell.data.integer),
        .number => cell.data.number,
        else => error.BadArgument,
    };
}

// -- ARITHMETIC --

fn add(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    switch (ret_type) {
        .integer => try hither.push(.{
            .tag = .integer,
            .data = .{
                .integer = std.math.add(i64, a.data.integer, b.data.integer) catch return error.ArithmeticOverflow,
            },
        }),

        .number => {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            try hither.push(.{ .tag = .number, .data = .{ .number = float_a + float_b } });
        },
        else => unreachable,
    }
}

fn subtract(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    switch (ret_type) {
        .integer => try hither.push(.{
            .tag = .integer,
            .data = .{
                .integer = std.math.sub(i64, b.data.integer, a.data.integer) catch return error.ArithmeticOverflow,
            },
        }),
        .number => {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            try hither.push(.{ .tag = .number, .data = .{ .number = float_b - float_a } });
        },
        else => unreachable,
    }
}

fn multiply(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    switch (ret_type) {
        .integer => try hither.push(.{
            .tag = .integer,
            .data = .{
                .integer = std.math.mul(i64, a.data.integer, b.data.integer) catch return error.ArithmeticOverflow,
            },
        }),
        .number => {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            try hither.push(.{ .tag = .number, .data = .{ .number = float_a * float_b } });
        },
        else => unreachable,
    }
}

fn divide(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    switch (ret_type) {
        .integer => try hither.push(.{
            .tag = .integer,
            .data = .{ .integer = std.math.divTrunc(i64, b.data.integer, a.data.integer) catch |err| switch (err) {
                error.DivisionByZero => return error.ZeroDenominator,
                error.Overflow => return error.ArithmeticOverflow,
            } },
        }),
        .number => {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (float_a == 0) return error.ZeroDenominator;
            try hither.push(.{ .tag = .number, .data = .{ .number = float_b / float_a } });
        },
        else => unreachable,
    }
}

fn modulo(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    switch (ret_type) {
        .integer => {
            if (a.data.integer == 0) return error.ZeroDenominator;
            try hither.push(.{ .tag = .integer, .data = .{ .integer = std.math.mod(i64, b.data.integer, a.data.integer) catch return error.BadArgument } });
        },
        .number => {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (float_a == 0) return error.ZeroDenominator;
            try hither.push(.{
                .tag = .number,
                .data = .{ .number = std.math.mod(f64, float_b, float_a) catch return error.BadArgument },
            });
        },
        else => unreachable,
    }
}

const zero: Cell = .{ .tag = .integer, .data = .{ .integer = 0 } };
const one: Cell = .{ .tag = .integer, .data = .{ .integer = 1 } };

// -- COMPARING --

fn greater(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const b = hither.pop() orelse return error.BadArgument;
    const a = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    try hither.push(switch (ret_type) {
        .integer => if (a.data.integer > b.data.integer) one else zero,
        .number => number: {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number zero;
            break :number if (float_a > float_b) one else zero;
        },
        else => unreachable,
    });
}

fn less(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const b = hither.pop() orelse return error.BadArgument;
    const a = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    try hither.push(switch (ret_type) {
        .integer => if (a.data.integer < b.data.integer) one else zero,
        .number => number: {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number zero;
            break :number if (float_a < float_b) one else zero;
        },
        else => unreachable,
    });
}

fn greaterEq(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const b = hither.pop() orelse return error.BadArgument;
    const a = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    try hither.push(switch (ret_type) {
        .integer => if (a.data.integer >= b.data.integer) one else zero,
        .number => number: {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number one;
            break :number if (float_a >= float_b) one else zero;
        },
        else => unreachable,
    });
}

fn lessEq(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const b = hither.pop() orelse return error.BadArgument;
    const a = hither.pop() orelse return error.BadArgument;
    const ret_type = try arithmeticCoerce(a.tag, b.tag);
    try hither.push(switch (ret_type) {
        .integer => if (a.data.integer <= b.data.integer) one else zero,
        .number => number: {
            const float_a = toNumber(a) catch unreachable;
            const float_b = toNumber(b) catch unreachable;
            if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) break :number one;
            break :number if (float_a <= float_b) one else zero;
        },
        else => unreachable,
    });
}

fn equal(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    if (a.tag != b.tag) {
        _ = arithmeticCoerce(a.tag, b.tag) catch {
            try hither.push(zero);
            return;
        };
        const float_a = toNumber(a) catch unreachable;
        const float_b = toNumber(b) catch unreachable;
        try hither.push(if (std.math.approxEqRel(f64, float_a, float_b, 10 * std.math.floatEps(f64))) one else zero);
        return;
    }
    if (a.eqlShallow(b)) {
        try hither.push(one);
        return;
    }
    if (a.tag != .slice) {
        try hither.push(zero);
        return;
    }
    if (a.slice_is == .definition or b.slice_is == .definition) {
        try hither.push(zero);
        return;
    }
    const slice_a = try toBytes(hither, a);
    const slice_b = try toBytes(hither, b);
    try hither.push(if (std.mem.eql(u8, slice_a, slice_b)) one else zero);
}

// -- STACK MANIPULATION --

fn dupe(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const cell = hither.pop() orelse return error.BadArgument;
    try hither.push(cell);
    try hither.push(cell);
}

fn swap(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    try hither.push(a);
    try hither.push(b);
}

fn heightIs(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const height: i64 = @intCast(hither.stack.len);
    try hither.push(.{ .tag = .integer, .data = .{ .integer = height } });
}

fn setTo(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const cell = hither.pop() orelse return error.BadArgument;
    if (cell.tag != .integer) return error.BadArgument;
    const height: usize = if (cell.data.integer < 0) 0 else @intCast(cell.data.integer);
    while (hither.stack.len < height) {
        try hither.push(zero);
    }
    hither.stack.len = height;
}

fn drop(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    _ = hither.pop();
}

// -- LOGIC --

fn andFn(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    try hither.push(if (a.eqlShallow(zero) or b.eqlShallow(zero)) zero else one);
}

fn orFn(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    try hither.push(if (a.eqlShallow(zero) and b.eqlShallow(zero)) zero else one);
}

fn notFn(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    try hither.push(if (a.eqlShallow(zero)) one else zero);
}

// -- misc --

fn print(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const writer = hither.output orelse return error.NotSupported;
    hither.printStack(writer) catch return error.IOError;
}

fn toBytes(hither: *Hither, cell: Cell) Error![]const u8 {
    if (cell.tag != .slice or cell.slice_is == .definition) return error.BadArgument;
    const ptr = hither.heap.fromAddress(cell.data.slice.address) orelse return error.BadArgument;
    return ptr[0..cell.data.slice.length];
}

fn toCells(hither: *Hither, cell: Cell) Error![]const Cell {
    if (cell.tag != .slice or cell.slice_is != .definition) return error.BadArgument;
    const byte_ptr = hither.heap.fromAddress(cell.data.slice.address) orelse return error.BadArgument;
    const ptr: [*]Cell = @ptrCast(@alignCast(byte_ptr));
    return ptr[0..cell.data.slice.length];
}

fn join(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const b = hither.pop() orelse return error.BadArgument;
    if (a.slice_is != b.slice_is) return error.BadArgument;
    if (a.slice_is == .word) return error.BadArgument;
    if (a.slice_is == .string) {
        const a_slice = try toBytes(hither, a);
        const b_slice = try toBytes(hither, b);
        const c_slice = try std.mem.concat(hither.heap.allocator(), u8, &.{ b_slice, a_slice });
        const address = hither.heap.addressOf(c_slice.ptr) catch unreachable;
        try hither.push(.{
            .tag = .slice,
            .data = .{ .slice = .{
                .address = address,
                .length = @intCast(c_slice.len),
            } },
        });
    } else {
        const a_slice = try toCells(hither, a);
        const b_slice = try toCells(hither, b);
        const c_slice = try std.mem.concat(hither.heap.allocator(), Cell, &.{ b_slice, a_slice });
        const address = hither.heap.addressOf(c_slice.ptr) catch unreachable;
        try hither.push(.{
            .tag = .slice,
            .slice_is = .definition,
            .data = .{ .slice = .{
                .address = address,
                .length = @intCast(c_slice.len),
            } },
        });
    }
}

// -- programming language-y things --

fn variable(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const a = hither.pop() orelse return error.BadArgument;
    const name = try toBytes(hither, a);
    if (std.mem.indexOfAny(u8, name, "\r\n\t ") != null) return error.BadArgument;
    const val = hither.pop() orelse return error.BadArgument;
    const slice = try hither.heap.allocator().alloc(Cell, 1);
    slice[0] = val;
    const addr = hither.heap.addressOf(slice.ptr) catch unreachable;
    if (hither.dictionary.count() == hither.dictionary.capacity()) return error.OutOfMemory;
    const res = hither.dictionary.getOrPutAssumeCapacity(name);
    res.key_ptr.* = name;
    res.value_ptr.* = .{
        .tag = .slice,
        .slice_is = .definition,
        .data = .{
            .slice = .{ .address = addr, .length = 1 },
        },
    };
}

fn call(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const cell = hither.pop() orelse return error.BadArgument;
    try hither.push(cell);
}

fn whileFn(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const cond = hither.pop() orelse return error.BadArgument;
    const func = hither.pop() orelse return error.BadArgument;
    while (true) {
        try hither.push(cond);
        const cell = hither.pop() orelse return error.BadArgument;
        if (cell.eqlShallow(zero)) break;
        try hither.push(func);
    }
}

fn noop(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
}

/// just leaves itself on top of the return stack, to be popped by isXt
/// exception: if the return stack satisfies isDeferred, pushes xt onto the stack instead
fn xt(hither: *Hither) Error!void {
    const self = hither.ret.pop();
    hither.ret.appendAssumeCapacity(self);
    if (try preamble(hither)) return;
    if (isDeferred(hither)) {
        if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
        hither.stack.appendAssumeCapacity(self);
    } else hither.ret.appendAssumeCapacity(self);
}

/// leaves itself on top of the return stack, to be popped by lambdaEnd
fn lambdaStart(hither: *Hither) Error!void {
    const this = hither.ret.pop();
    hither.ret.appendAssumeCapacity(this);
    if (try preamble(hither)) {
        hither.ret.appendAssumeCapacity(this);
        return;
    }
    // push the stack location onto the return stack for lambdaEnd to use it
    const height: Cell = .{
        .tag = .integer,
        .data = .{ .integer = @intCast(hither.stack.len) },
    };
    hither.ret.appendAssumeCapacity(height);
    if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
    hither.ret.appendAssumeCapacity(this);
}

/// leaves itself on top of the return stack, to be popped by then
fn ifStart(hither: *Hither) Error!void {
    const this = hither.ret.pop();
    hither.ret.appendAssumeCapacity(this);
    if (try preamble(hither)) {
        hither.ret.appendAssumeCapacity(this);
        return;
    }
    // push the stack location onto the return stack for then to use it
    const height: Cell = .{
        .tag = .integer,
        .data = .{ .integer = @intCast(hither.stack.len) },
    };
    hither.ret.appendAssumeCapacity(height);
    if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
    hither.ret.appendAssumeCapacity(this);
}

/// leaves itself on top of the return stack, to be popped by then
fn elseStart(hither: *Hither) Error!void {
    const this = hither.ret.pop();
    defer hither.ret.appendAssumeCapacity(this);
    const other = hither.ret.popOrNull() orelse return error.PairMismatch;
    {
        defer hither.ret.appendAssumeCapacity(other);
        const if_cell: Cell = .{
            .tag = .builtin,
            .data = .{ .builtin = @field(@This(), "ifStart") },
        };
        if (!other.eqlShallow(if_cell)) return error.PairMismatch;
        hither.ret.appendAssumeCapacity(this);
        if (try preamble(hither)) return;
    }
    // push the stack location onto the return stack for then to use it
    const height: Cell = .{
        .tag = .integer,
        .data = .{ .integer = @intCast(hither.stack.len) },
    };
    if (hither.ret.len == hither.ret.capacity - 1) return error.StackOverflow;
    hither.ret.appendAssumeCapacity(height);
}

fn captureFrom(hither: *Hither, location: usize) Error!Cell {
    if (location > hither.stack.len) return error.BadArgument;
    const slice = try hither.heap.allocator().alloc(Cell, hither.stack.len - location);
    defer hither.stack.len = location;
    for (slice, location..) |*datum, i| {
        datum.* = hither.stack.get(i);
    }
    const addr = hither.heap.addressOf(slice.ptr) catch return .{
        .tag = .slice,
        .slice_is = .definition,
        .data = .{
            .slice = .{ .address = 0, .length = 0 },
        },
    };
    return .{
        .tag = .slice,
        .slice_is = .definition,
        .data = .{
            .slice = .{ .address = addr, .length = @intCast(slice.len) },
        },
    };
}

fn then(hither: *Hither) Error!void {
    const this = hither.ret.pop();
    const else_cell: Cell = .{
        .tag = .builtin,
        .data = .{ .builtin = @field(@This(), "elseStart") },
    };
    const if_cell: Cell = .{
        .tag = .builtin,
        .data = .{ .builtin = @field(@This(), "ifStart") },
    };

    const other = hither.ret.popOrNull() orelse return error.PairMismatch;
    if (other.eqlShallow(else_cell)) {
        const loc_or_if = hither.ret.popOrNull() orelse return error.PairMismatch;
        if (loc_or_if.eqlShallow(if_cell)) {
            hither.ret.appendAssumeCapacity(this);
            if (try preamble(hither)) return;
            return error.PairMismatch;
        }
        if (loc_or_if.tag != .integer) return error.PairMismatch;

        const should_be_if = hither.ret.popOrNull() orelse return error.PairMismatch;
        if (!should_be_if.eqlShallow(if_cell)) return error.PairMismatch;
        const if_loc = hither.ret.popOrNull() orelse return error.PairMismatch;
        if (if_loc.tag != .integer) return error.PairMismatch;

        const else_slice = try captureFrom(hither, @intCast(loc_or_if.data.integer));
        const if_slice = try captureFrom(hither, @intCast(if_loc.data.integer));
        const cond = hither.pop() orelse return error.BadArgument;
        if (cond.eqlShallow(zero)) try hither.push(else_slice) else try hither.push(if_slice);
    } else if (other.eqlShallow(if_cell)) {
        hither.ret.appendAssumeCapacity(this);
        if (try preamble(hither)) return;
        const location = hither.ret.popOrNull() orelse return error.PairMismatch;
        if (location.tag != .integer) return error.PairMismatch;

        const if_slice = try captureFrom(hither, @intCast(location.data.integer));
        const cond = hither.pop() orelse return error.BadArgument;
        if (cond.eqlShallow(zero)) return;
        try hither.push(if_slice);
    } else return error.PairMismatch;
}

fn lambdaEnd(hither: *Hither) Error!void {
    const this = hither.ret.pop();
    const other = hither.ret.popOrNull() orelse return error.PairMismatch;
    const lambda_cell: Cell = .{
        .tag = .builtin,
        .data = .{ .builtin = @field(@This(), "lambdaStart") },
    };
    if (!other.eqlShallow(lambda_cell)) return error.PairMismatch;
    hither.ret.appendAssumeCapacity(this);
    if (try preamble(hither)) return;
    const lambda_loc = hither.ret.popOrNull() orelse return error.PairMismatch;
    if (lambda_loc.tag != .integer) return error.PairMismatch;
    const slice = try captureFrom(hither, @intCast(lambda_loc.data.integer));
    if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
    hither.stack.appendAssumeCapacity(slice);
}

fn exit(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    var idx = hither.ret.popOrNull() orelse return;
    if (idx.tag != .integer) return error.BadArgument;
    idx.data.integer = -1;
    hither.ret.appendAssumeCapacity(idx);
}

// significantly more verbose than a simple for loop so that it can be interrupted by `exit`
pub fn iterateThrough(hither: *Hither) Error!void {
    const slice = hither.ret.pop();
    hither.ret.appendAssumeCapacity(slice);
    if (try preamble(hither)) return;
    hither.ret.appendAssumeCapacity(slice);
    defer _ = hither.ret.popOrNull();
    const cells = try toCells(hither, slice);
    const pc_loc = hither.ret.len;
    if (hither.ret.len == hither.ret.capacity) return error.StackOverflow;
    hither.ret.appendAssumeCapacity(zero);
    defer _ = hither.ret.popOrNull();
    var program_counter: u32 = 0;
    while (program_counter < slice.data.slice.length) {
        try hither.push(cells[program_counter]);
        var pc = hither.ret.get(pc_loc);
        // blk: {
        // const writer = hither.output orelse break :blk;
        // hither.dumpState(writer) catch {};
        // }
        if (pc.tag != .integer or pc.data.integer < 0) break;
        pc.data.integer += 1;
        program_counter = @intCast(pc.data.integer);
        hither.ret.set(pc_loc, pc);
    }
}

pub fn lookUpWord(hither: *Hither) Error!void {
    const slice = hither.ret.pop();
    const bytes = try toBytes(hither, slice);
    const definition = hither.dictionary.get(bytes) orelse {
        hither.ret.appendAssumeCapacity(slice);
        if (try preamble(hither)) return;
        return error.WordNotFound;
    };
    if (isXt(hither) or isDeferred(hither)) {
        if (hither.stack.len == hither.stack.capacity) return error.StackOverflow;
        switch (definition.tag) {
            .builtin => try hither.push(definition),
            .slice => hither.stack.appendAssumeCapacity(slice),
            else => unreachable,
        }
        return;
    }
    try hither.push(definition);
}

fn dumpState(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    hither.dumpState(hither.output orelse return error.NotSupported) catch return error.IOError;
}

fn inspect(hither: *Hither) Error!void {
    if (try preamble(hither)) return;
    const writer = hither.output orelse return error.NotSupported;
    const slice = hither.stack.popOrNull() orelse return error.BadArgument;
    const bytes = try toBytes(hither, slice);
    const defn = hither.dictionary.get(bytes) orelse return error.WordNotFound;
    inspectInner(hither, writer, bytes, defn) catch return error.IOError;
}

fn inspectInner(hither: *Hither, writer: std.io.AnyWriter, name: []const u8, defn: Cell) !void {
    const inner = try toCells(hither, defn);
    try writer.print("DEFINITION OF: {s}\n", .{name});
    for (inner) |c| {
        switch (c.tag) {
            .slice => {
                if (c.slice_is != .definition) {
                    const bytes = try toBytes(hither, c);
                    try writer.writeAll(bytes);
                    try writer.writeAll("\n");
                } else try writer.print("{}\n", .{c});
            },
            else => try writer.print("{}\n", .{c}),
        }
    }
}

fn breakFn(hither: *Hither) Error!void {
    hither.flush();
}

test "ref" {
    _ = keys;
    _ = vals;
}

const Hither = @import("hither.zig");
const Cell = Hither.Cell;
const Error = Hither.Error;
const std = @import("std");
