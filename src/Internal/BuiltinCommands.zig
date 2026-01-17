const std = @import("std");
const console = @import("Commands.zig");
const outerShell = @import("OuterShell.zig");
pub fn registerBuiltInCommands(builder: *console.ConsoleAppBuilder, allocator: std.mem.Allocator) !void {
    try builder.addCommand(allocator, "exit", handleExit);
    try builder.addCommand(allocator, "echo", handleEcho);
    try builder.addCommand(allocator, "type", handleType);
    try builder.addCommand(allocator, "pwd", handlePwd);
try builder.addCommand(allocator, "cd", handleCd);
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
pub fn handlePwd(ctx: console.CommandContext) !void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch {
        try ctx.output_writer.print("pwd: error getting current directory\n", .{});
        return;
    };
    try ctx.output_writer.print("{s}\n", .{cwd});
}
pub fn handleCd(ctx: console.CommandContext) !void {
    const path = blk: {
        if (ctx.args.len == 0 or std.mem.eql(u8, ctx.args, "~")) {
            // cd or cd ~ -> go to HOME
            break :blk std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.output_writer.print("cd: HOME not set\n", .{});
                return;
            };
        } else if (std.mem.startsWith(u8, ctx.args, "~/")) {
            // cd ~/something -> expand ~ to HOME
            const home = std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.output_writer.print("cd: HOME not set\n", .{});
                return;
            };
            break :blk std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ home, ctx.args[1..] }) catch {
                try ctx.output_writer.print("cd: error\n", .{});
                return;
            };
        } else {
            break :blk ctx.args;
        }
    };

    std.posix.chdir(path) catch {
        try ctx.output_writer.print("cd: {s}: No such file or directory\n", .{path});
        return;
    };
}
