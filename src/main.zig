const std = @import("std");

pub fn main() !void {

    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;
    try stdout.print("$ ", .{});
    
    var input_buffer: [4096]u8 = undefined;
    var input_reader = std.fs.File.stdin().readerStreaming(&input_buffer);
    const input_i = &input_reader.interface;

    if (try input_i.takeDelimiter('\n')) |cmd| {
        const command = std.mem.trimRight(u8, cmd, "\r");
        try stdout.print("{s}: command not found\n", .{command});
        try stdout.flush();
    }
}
