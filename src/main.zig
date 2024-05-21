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

    var stack = try hither.init(allocator, 1024, 1024, 1024 * 1024);
    defer stack.deinit(allocator);

    var quit = false;
    try stdout.print("type some hither code!\n", .{});
    while (!quit) {
        try stdout.print("> ", .{});
        try bw.flush();
        switch (stack.parse(stdin.any(), stdout.any())) {
            .err => {
                defer stack.flush();
                try stderr.print("{s}\n", .{stack.msg});
                try stderr_buf.flush();
            },
            .quit => quit = true,
            .ok => {
                defer stack.flush();
                if (stack.stack.len != 0) try stack.printStack(stdout.any());
                try stdout.print("ok\n", .{});
                try bw.flush();
            },
            .incomplete => {
                try stack.dumpState(stdout.any());
                try bw.flush();
            },
        }
    }
}

const std = @import("std");
const hither = @import("hither");
