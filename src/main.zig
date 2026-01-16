const std = @import("std");

pub fn main() !void {
    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;
    // TODO: Uncomment the code below to pass the first stage
    var input_buffer: [4096]u8 = undefined;
    var input_reader = std.fs.File.stdin().readerStreaming(&input_buffer);
    const input_i = &input_reader.interface;

    const command = try input_i.takeDelimiter('\n');
    if (command) |command_value| {
        try stdout.print("{s} command not found\n", .{command_value});
    } else {
        try stdout.print("Invalid input", .{});
    }
}
