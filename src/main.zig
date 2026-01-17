const std = @import("std");
const console = @import("./Internal/Commands.zig");
const builtinCommands = @import("Internal/BuiltinCommands.zig");
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var builder = console.ConsoleAppBuilder{
        .commands = .empty,
    };
    defer builder.deinit(allocator);
    var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
    const stdout = &stdout_writer.interface;

    var input_buffer: [4096]u8 = undefined;
    var input_reader = std.fs.File.stdin().readerStreaming(&input_buffer);
    const input_i = &input_reader.interface;

    builder.addWriter(stdout);
    try builtinCommands.registerBuiltInCommands(&builder, allocator);
    var app = builder.build();

    app.run();
    while (app.is_running) {
        defer _ = arena.reset(.retain_capacity);

        try stdout.print("$ ", .{});
        try stdout.flush();
        const raw_input = (try input_i.takeDelimiter('\n')) orelse "";
        const command_input = std.mem.trimRight(u8, raw_input, "\r");

        const first_space_index = std.mem.indexOfScalar(u8, command_input, ' ') orelse command_input.len;
        const cmd = command_input[0..first_space_index];
        const args = if (first_space_index < command_input.len) command_input[first_space_index + 1 ..] else "";

        try app.handleCommand(arena.allocator(), cmd, args, command_input);

        try stdout.flush();
    }


}
