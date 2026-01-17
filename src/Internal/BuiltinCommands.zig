const std = @import("std");
const console = @import("Commands.zig");
const Bookmarks = @import("Bookmarks.zig").Bookmarks;

pub fn registerBuiltInCommands(builder: *console.ConsoleAppBuilder) !void {
    try builder.addCommand("exit", handleExit);
    try builder.addCommand("echo", handleEcho);
    try builder.addCommand("type", handleType);
    try builder.addCommand("pwd", handlePwd);
    try builder.addCommand("cd", handleCd);
    try builder.addCommand("mark", handleMark);
    try builder.addCommand("jump", handleJump);
    try builder.addCommand("jumpt", handleJumpt);
    try builder.addCommand("marks", handleMarks);
    try builder.addCommand("unmark", handleUnmark);
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

fn handleMark(ctx: console.CommandContext) !void {
    if (ctx.args.len == 0) {
        try ctx.terminal.print("mark: missing bookmark name\n", .{});
        return;
    }
    const name = ctx.args[0];

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &buf) catch {
        try ctx.terminal.print("mark: error getting current directory\n", .{});
        return;
    };

    var bookmarks = Bookmarks.load(ctx.allocator) catch {
        try ctx.terminal.print("mark: error loading bookmarks\n", .{});
        return;
    };
    defer bookmarks.deinit();

    bookmarks.add(name, cwd) catch {
        try ctx.terminal.print("mark: error saving bookmark\n", .{});
        return;
    };

    bookmarks.save() catch {
        try ctx.terminal.print("mark: error saving bookmarks file\n", .{});
        return;
    };
}

fn handleJump(ctx: console.CommandContext) !void {
    if (ctx.args.len == 0) {
        try ctx.terminal.print("jump: missing bookmark name\n", .{});
        return;
    }
    const name = ctx.args[0];

    var bookmarks = Bookmarks.load(ctx.allocator) catch {
        try ctx.terminal.print("jump: error loading bookmarks\n", .{});
        return;
    };
    defer bookmarks.deinit();

    if (bookmarks.get(name)) |path| {
        std.posix.chdir(path) catch {
            try ctx.terminal.print("jump: {s}: No such file or directory\n", .{path});
            return;
        };
    } else {
        try ctx.terminal.print("jump: bookmark '{s}' not found\n", .{name});
    }
}

fn handleJumpt(ctx: console.CommandContext) !void {
    if (ctx.args.len == 0) {
        try ctx.terminal.print("jumpt: missing bookmark name\n", .{});
        return;
    }
    const name = ctx.args[0];

    var bookmarks = Bookmarks.load(ctx.allocator) catch {
        try ctx.terminal.print("jumpt: error loading bookmarks\n", .{});
        return;
    };
    defer bookmarks.deinit();

    if (bookmarks.get(name)) |path| {
        const cmd = std.fmt.allocPrint(ctx.allocator, "start powershell.exe -NoExit -Command \"cd '{s}'\"", .{path}) catch {
            try ctx.terminal.print("jumpt: allocation error\n", .{});
            return;
        };
        defer ctx.allocator.free(cmd);

        var child = std.process.Child.init(&.{ "cmd.exe", "/c", cmd }, ctx.allocator);
        _ = child.spawn() catch {
            try ctx.terminal.print("jumpt: failed to open terminal\n", .{});
            return;
        };
    } else {
        try ctx.terminal.print("jumpt: bookmark '{s}' not found\n", .{name});
    }
}

fn handleMarks(ctx: console.CommandContext) !void {
    var bookmarks = Bookmarks.load(ctx.allocator) catch {
        try ctx.terminal.print("marks: error loading bookmarks\n", .{});
        return;
    };
    defer bookmarks.deinit();

    var iter = bookmarks.map.iterator();
    while (iter.next()) |entry| {
        try ctx.write("{s} -> {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

fn handleUnmark(ctx: console.CommandContext) !void {
    if (ctx.args.len == 0) {
        try ctx.terminal.print("unmark: missing bookmark name\n", .{});
        return;
    }
    const name = ctx.args[0];

    var bookmarks = Bookmarks.load(ctx.allocator) catch {
        try ctx.terminal.print("unmark: error loading bookmarks\n", .{});
        return;
    };
    defer bookmarks.deinit();

    if (bookmarks.remove(name)) {
        bookmarks.save() catch {
            try ctx.terminal.print("unmark: error saving bookmarks file\n", .{});
            return;
        };
    } else {
        try ctx.terminal.print("unmark: bookmark '{s}' not found\n", .{name});
    }
}
