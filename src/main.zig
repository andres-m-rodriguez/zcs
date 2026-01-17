const std = @import("std");
const ConsoleAppBuilder = @import("Internal/Commands.zig").ConsoleAppBuilder;
const builtins = @import("Internal/BuiltinCommands.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var builder = ConsoleAppBuilder.init(allocator);
    defer builder.deinit();

    try builtins.registerBuiltInCommands(&builder);

    var app = try builder.build();
    defer app.deinit();

    const args = std.process.argsAlloc(allocator) catch {
        try app.runShell();
        return;
    };
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        try app.runCli(args);
    } else {
        try app.runShell();
    }
}
