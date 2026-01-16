const std = @import("std");

pub fn main() !void {
    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;

    var input_buffer: [4096]u8 = undefined;
    var input_reader = std.fs.File.stdin().readerStreaming(&input_buffer);
    const input_i = &input_reader.interface;
    var is_running = true;
    while (is_running) {
        try stdout.print("$ ", .{});
        const command_input = try input_i.takeDelimiter('\n') orelse "";

        const command = std.mem.trimRight(u8, command_input, "\r");
        if (std.mem.eql(u8, command, "exit")) {
            is_running = false;
        } else if (std.mem.eql(u8, command[0..4], "echo")) {
            const echo_output = command[4..];
            try stdout.print("{s}\n", .{echo_output});
        } else {
            try stdout.print("{s}: command not found\n", .{command});
        }
        try stdout.flush();
    }
}
