const std = @import("std");
const console = @import("./Internal/Commands.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
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
    try builder.addCommand(allocator, "echo", handleEcho);
    try builder.addCommand(allocator, "exit", handleExit);
    try builder.addCommand(allocator, "type", handleType);
    var app = builder.build();

    app.run();
    while (app.is_running) {
        try stdout.print("$ ", .{});
        const raw_input = (try input_i.takeDelimiter('\n')) orelse "";
        const command_input = std.mem.trimRight(u8, raw_input, "\r");
        const first_space_index = std.mem.indexOfScalar(u8, command_input, ' ');

        if (first_space_index) |index| {
            const is_command_found = try app.handleCommand(
                command_input[0..index],
                command_input[index + 1 ..],
                command_input,
            );

            if (is_command_found == false) {
                try stdout.print("{s} command not found \n", .{command_input[0..index]});
            }
        } else {
            const is_command_found = try app.handleCommand(command_input, command_input, command_input);
            if (is_command_found == false) {
                try stdout.print("{s} command not found \n", .{command_input});
            }
        }

        try stdout.flush();
    }
}

pub fn handleExit(ctx: console.CommandContext) !void {
    ctx.app.is_running = false;
}
pub fn handleEcho(ctx: console.CommandContext) !void {
    try ctx.output_writer.print("{s}\n", .{ctx.args});
}
pub fn handleType(ctx: console.CommandContext) !void {
    const built_in_command = ctx.app.findBuiltInCommand(ctx.args);
    if (built_in_command) |_| {
        try ctx.output_writer.print("{s} is a shell builtin \n", .{ctx.args});
    } else {
        try ctx.output_writer.print("{s} command not found \n", .{ctx.args});
    }
}
