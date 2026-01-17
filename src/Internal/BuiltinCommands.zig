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
    for (ctx.args, 0..) |arg, i| {
        if (i > 0) try ctx.write(" ", .{});
        try ctx.write("{s}", .{arg});
    }
    try ctx.write("\n", .{});
}

fn handleType(ctx: console.CommandContext) !void {
    if (ctx.args.len == 0) {
        try ctx.terminal.print("type: missing argument\n", .{});
        return;
    }
    const name = ctx.args[0];
    if (ctx.app.findBuiltInCommand(name)) |_| {
        try ctx.write("{s} is a shell builtin\n", .{name});
        return;
    }
    if (ctx.app.outer_shell.findExecutable(name)) |path| {
        try ctx.write("{s} is {s}\n", .{ name, path });
    } else {
        try ctx.write("{s}: not found\n", .{name});
    }
}

fn handlePwd(ctx: console.CommandContext) !void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch {
        try ctx.terminal.print("pwd: error getting current directory\n", .{});
        return;
    };
    try ctx.write("{s}\n", .{cwd});
}

fn handleCd(ctx: console.CommandContext) !void {
    const arg = if (ctx.args.len > 0) ctx.args[0] else "";

    const path = blk: {
        if (arg.len == 0 or std.mem.eql(u8, arg, "~")) {
            break :blk std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.terminal.print("cd: HOME not set\n", .{});
                return;
            };
        } else if (std.mem.startsWith(u8, arg, "~/")) {
            const home = std.process.getEnvVarOwned(ctx.allocator, "HOME") catch {
                try ctx.terminal.print("cd: HOME not set\n", .{});
                return;
            };
            break :blk std.fmt.allocPrint(ctx.allocator, "{s}{s}", .{ home, arg[1..] }) catch {
                try ctx.terminal.print("cd: error\n", .{});
                return;
            };
        } else {
            break :blk arg;
        }
    };

    std.posix.chdir(path) catch {
        try ctx.terminal.print("cd: {s}: No such file or directory\n", .{path});
        return;
    };
}
