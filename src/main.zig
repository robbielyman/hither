/// hither repl
pub fn main() !void {
    const stdin = std.io.getStdIn().reader();
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    const stderr_file = std.io.getStdErr().writer();
    var stderr_buf = std.io.bufferedWriter(stderr_file);
    const stderr = stderr_buf.writer();

    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const buf = try allocator.alignedAlloc(u8, @alignOf(hither.Cell), 128 * 1024 * 1024);
    defer allocator.free(buf);

    var stack = try hither.init(buf);

    var quit = false;
    try stdout.print("type some hither code!\n", .{});
    while (!quit) {
        try stdout.print("> ", .{});
        try bw.flush();
        switch (stack.parse(stdin)) {
            .err => {
                defer stack.flush();
                try stderr.print("error: {s}\n", .{stack.msg});
                try stderr_buf.flush();
            },
            .quit => quit = true,
            else => {},
        }
        if (quit) break;
        switch (stack.tick()) {
            .err => {
                defer stack.flush();
                try stderr.print("error: {s}\n", .{stack.msg});
                try stderr_buf.flush();
            },
            .ok => {
                defer stack.flush();
                if (stack.msg.len > 0)
                    try stdout.print("{s}\n", .{stack.msg});
                try stdout.print("ok\n", .{});
                try bw.flush();
            },
            .quit => quit = true,
            .incomplete => {},
        }
    }
}

const std = @import("std");
const hither = @import("hither");
