const std = @import("std");
const console = @import("Commands.zig");
const outerShell = @import("OuterShell.zig");
pub fn registerBuiltInCommands(builder: *console.ConsoleAppBuilder, allocator: std.mem.Allocator) !void {
    try builder.addCommand(allocator, "exit", handleExit);
    try builder.addCommand(allocator, "echo", handleEcho);
    try builder.addCommand(allocator, "type", handleType);
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
        try ctx.output_writer.print("{s} is a shell builtin\n", .{ctx.args});
        return;
    }
    if (outerShell.findExecutable(ctx.allocator, ctx.args)) |path| {
        try ctx.output_writer.print("{s} is {s}\n", .{ ctx.args, path });
    } else {
        try ctx.output_writer.print("{s}: not found\n", .{ctx.args});
    }
}
