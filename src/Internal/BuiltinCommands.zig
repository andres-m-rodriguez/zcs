const std = @import("std");
const console = @import("Commands.zig");

pub fn registerBuiltInCommands(builder: *console.ConsoleAppBuilder) !void {
    try builder.addCommand("exit", handleExit);
    try builder.addCommand("echo", handleEcho);
    try builder.addCommand("type", handleType);
    try builder.addCommand("pwd", handlePwd);
    try builder.addCommand("cd", handleCd);
}

fn handleExit(ctx: console.CommandContext) !void {
    ctx.app.stop();
}

fn handleEcho(ctx: console.CommandContext) !void {
    try ctx.terminal.print("{s}\n", .{ctx.args});
}

fn handleType(ctx: console.CommandContext) !void {
    if (ctx.app.findBuiltInCommand(ctx.args)) |_| {
        try ctx.terminal.print("{s} is a shell builtin\n", .{ctx.args});
        return;
    }
    if (ctx.app.outer_shell.findExecutable(ctx.args)) |path| {
        try ctx.terminal.print("{s} is {s}\n", .{ ctx.args, path });
    } else {
        try ctx.terminal.print("{s}: not found\n", .{ctx.args});
    }
}

fn handlePwd(ctx: console.CommandContext) !void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch {
        try ctx.terminal.print("pwd: error getting current directory\n", .{});
        return;
    };
    try ctx.terminal.print("{s}\n", .{cwd});
}

fn handleCd(ctx: console.CommandContext) !void {
    const path = blk: {
        if (ctx.args.len == 0 or std.mem.eql(u8, ctx.args, "~")) {
            break :blk std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.terminal.print("cd: HOME not set\n", .{});
                return;
            };
        } else if (std.mem.startsWith(u8, ctx.args, "~/")) {
            const home = std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.terminal.print("cd: HOME not set\n", .{});
                return;
            };
            break :blk std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ home, ctx.args[1..] }) catch {
                try ctx.terminal.print("cd: error\n", .{});
                return;
            };
        } else {
            break :blk ctx.args;
        }
    };

    std.posix.chdir(path) catch {
        try ctx.terminal.print("cd: {s}: No such file or directory\n", .{path});
        return;
    };
}
