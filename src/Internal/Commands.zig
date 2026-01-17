const std = @import("std");
const OuterShell = @import("OuterShell.zig").OuterShell;
const Terminal = @import("Terminal.zig").Terminal;
const Key = @import("Terminal.zig").Key;
const Parser = @import("Parser.zig");

pub const Handler = *const fn (ctx: CommandContext) anyerror!void;

pub const CommandContext = struct {
    app: *ConsoleApp,
    terminal: *Terminal,
    allocator: std.mem.Allocator,
    command_name: []const u8,
    args: []const []const u8,
    raw_input: []const u8,
    stdout_file: ?std.fs.File = null,
    stderr_file: ?std.fs.File = null,

    pub fn write(self: *const CommandContext, comptime fmt: []const u8, args_fmt: anytype) !void {
        if (self.stdout_file) |file| {
            var buf: [4096]u8 = undefined;
            var writer = file.writerStreaming(&buf);
            try writer.interface.print(fmt, args_fmt);
            try writer.interface.flush();
        } else {
            try self.terminal.print(fmt, args_fmt);
        }
    }

    pub fn writeErr(self: *const CommandContext, comptime fmt: []const u8, args_fmt: anytype) !void {
        if (self.stderr_file) |file| {
            var buf: [4096]u8 = undefined;
            var writer = file.writerStreaming(&buf);
            try writer.interface.print(fmt, args_fmt);
            try writer.interface.flush();
        } else {
            try self.terminal.print(fmt, args_fmt);
        }
    }
};

pub const ConsoleAppBuilder = struct {
    commands: std.StringHashMapUnmanaged(Handler) = .{},
    allocator: std.mem.Allocator,
    prompt: []const u8 = "$ ",

    pub fn init(allocator: std.mem.Allocator) ConsoleAppBuilder {
        return .{ .allocator = allocator };
    }

    pub fn addCommand(self: *ConsoleAppBuilder, comptime name: []const u8, handler: Handler) !void {
        const name_lower = comptime comptimeLower(name);
        try self.commands.put(self.allocator, name_lower, handler);
    }

    pub fn setPrompt(self: *ConsoleAppBuilder, prompt: []const u8) void {
        self.prompt = prompt;
    }

    pub fn build(self: *ConsoleAppBuilder) !ConsoleApp {
        const outer_shell = try OuterShell.init(self.allocator);
        return ConsoleApp{
            .builder = self,
            .outer_shell = outer_shell,
            .allocator = self.allocator,
            .is_running = false,
        };
    }

    pub fn deinit(self: *ConsoleAppBuilder) void {
        self.commands.deinit(self.allocator);
    }
};

pub const ConsoleApp = struct {
    builder: *ConsoleAppBuilder,
    outer_shell: OuterShell,
    allocator: std.mem.Allocator,
    is_running: bool,

    pub fn deinit(self: *ConsoleApp) void {
        self.outer_shell.deinit();
    }

    pub fn runShell(self: *ConsoleApp) !void {
        var terminal = try Terminal.init();
        defer terminal.deinit();

        self.is_running = true;

        var line = std.ArrayList(u8){};
        defer line.deinit(self.allocator);

        var tab_index: usize = 0;
        var current_matches: []const []const u8 = &.{};
        var completion_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer completion_arena.deinit();
        var original_prefix: []const u8 = &.{};
        var display_len: usize = 0;
        var dropdown_open = false;

        try terminal.print("{s}", .{self.builder.prompt});
        try terminal.flush();

        while (self.is_running) {
            const key = try Key.read(&terminal);

            switch (key) {
                .enter => {
                    if (dropdown_open) {
                        try self.clearDropdown(&terminal, current_matches.len);
                        dropdown_open = false;
                    }

                    try terminal.print("\n", .{});
                    try terminal.flush();

                    if (line.items.len > 0) {
                        var parsed = try Parser.parse(self.allocator, line.items);
                        defer parsed.deinit(self.allocator);

                        if (parsed.executable.len > 0) {
                            try self.handleCommand(&terminal, parsed.executable, parsed.args, line.items, parsed.stdout_redirect, parsed.stderr_redirect, parsed.stdout_append, parsed.stderr_append);
                            try terminal.flush();
                        }
                    }

                    line.clearRetainingCapacity();
                    tab_index = 0;
                    current_matches = &.{};
                    _ = completion_arena.reset(.retain_capacity);
                    original_prefix = &.{};
                    display_len = 0;

                    if (self.is_running) {
                        try terminal.print("{s}", .{self.builder.prompt});
                        try terminal.flush();
                    }
                },
                .tab => {
                    if (current_matches.len == 0) {
                        _ = completion_arena.reset(.retain_capacity);
                        original_prefix = try completion_arena.allocator().dupe(u8, line.items);
                        current_matches = try self.findCompletions(completion_arena.allocator(), original_prefix);
                        tab_index = 0;
                        display_len = line.items.len;
                        // TODO: Remove bell sound later
                        if (current_matches.len == 0) {
                            try terminal.print("\x07", .{});
                        }
                    }

                    if (current_matches.len > 0) {
                        if (tab_index >= current_matches.len) {
                            tab_index = 0;
                        }
                        const match = current_matches[tab_index];

                        for (0..display_len) |_| {
                            try terminal.backspace();
                        }

                        line.clearRetainingCapacity();
                        try line.appendSlice(self.allocator, match);
                        display_len = match.len;
                        if (current_matches.len == 1) {
                            try line.append(self.allocator, ' ');
                        }

                        try terminal.print("{s} ", .{match});

                        if (current_matches.len > 1) {
                            try self.renderDropdown(&terminal, current_matches, tab_index);
                            dropdown_open = true;
                        }

                        try terminal.flush();
                        tab_index += 1;
                    }
                },
                .up => {
                    if (dropdown_open and current_matches.len > 0) {
                        if (tab_index == 0) {
                            tab_index = current_matches.len - 1;
                        } else {
                            tab_index -= 1;
                        }
                        try self.updateSelection(&terminal, &line, current_matches, tab_index, &display_len);
                    }
                },
                .down => {
                    if (dropdown_open and current_matches.len > 0) {
                        tab_index += 1;
                        if (tab_index >= current_matches.len) {
                            tab_index = 0;
                        }
                        try self.updateSelection(&terminal, &line, current_matches, tab_index, &display_len);
                    }
                },
                .escape => {
                    if (dropdown_open) {
                        try self.clearDropdown(&terminal, current_matches.len);
                        dropdown_open = false;
                        current_matches = &.{};
                        tab_index = 0;
                        try terminal.flush();
                    }
                },
                .backspace => {
                    if (dropdown_open) {
                        try self.clearDropdown(&terminal, current_matches.len);
                        dropdown_open = false;
                    }
                    if (line.items.len > 0) {
                        _ = line.pop();
                        try terminal.backspace();
                        try terminal.flush();
                        display_len = line.items.len;
                    }
                    tab_index = 0;
                    current_matches = &.{};
                },
                .char => |c| {
                    if (dropdown_open) {
                        try self.clearDropdown(&terminal, current_matches.len);
                        dropdown_open = false;
                    }
                    try line.append(self.allocator, c);
                    try terminal.print("{c}", .{c});
                    try terminal.flush();
                    display_len = line.items.len;
                    tab_index = 0;
                    current_matches = &.{};
                },
                else => {
                    tab_index = 0;
                    current_matches = &.{};
                },
            }
        }
    }

    pub fn runCli(self: *ConsoleApp, args: []const []const u8) !void {
        if (args.len < 2) {
            var buf: [1024]u8 = undefined;
            var stderr = std.fs.File.stderr().writerStreaming(&buf);
            try stderr.interface.print("Usage: {s} <command> [args...]\n", .{args[0]});
            try stderr.interface.flush();
            return;
        }

        var terminal = try Terminal.init();
        defer terminal.deinit();

        const command_name = args[1];
        try self.handleCommand(&terminal, command_name, args[2..], command_name, null, null, false, false);
        try terminal.flush();
    }

    fn handleCommand(self: *ConsoleApp, terminal: *Terminal, command_name: []const u8, args: []const []const u8, raw_input: []const u8, stdout_redirect: ?[]const u8, stderr_redirect: ?[]const u8, stdout_append: bool, stderr_append: bool) !void {
        var stdout_file: ?std.fs.File = null;
        defer if (stdout_file) |f| f.close();

        var stderr_file: ?std.fs.File = null;
        defer if (stderr_file) |f| f.close();

        if (stdout_redirect) |path| {
            stdout_file = std.fs.cwd().createFile(path, .{ .truncate = !stdout_append }) catch |err| {
                try terminal.print("cannot open {s}: {}\n", .{ path, err });
                return;
            };
            if (stdout_append) {
                stdout_file.?.seekFromEnd(0) catch {};
            }
        }

        if (stderr_redirect) |path| {
            stderr_file = std.fs.cwd().createFile(path, .{ .truncate = !stderr_append }) catch |err| {
                try terminal.print("cannot open {s}: {}\n", .{ path, err });
                return;
            };
            if (stderr_append) {
                stderr_file.?.seekFromEnd(0) catch {};
            }
        }

        const ctx = CommandContext{
            .app = self,
            .terminal = terminal,
            .allocator = self.allocator,
            .command_name = command_name,
            .args = args,
            .raw_input = raw_input,
            .stdout_file = stdout_file,
            .stderr_file = stderr_file,
        };

        if (self.findBuiltInCommand(command_name)) |handler| {
            try handler(ctx);
            return;
        }

        if (self.outer_shell.findExecutable(command_name)) |_| {
            try self.outer_shell.executeCommandParsed(command_name, args, stdout_file, stderr_file);
            return;
        }

        try terminal.print("{s}: command not found\n", .{command_name});
    }

    pub fn findBuiltInCommand(self: *ConsoleApp, name: []const u8) ?Handler {
        var lower_buf: [256]u8 = undefined;
        const name_lower = std.ascii.lowerString(lower_buf[0..name.len], name);
        return self.builder.commands.get(name_lower);
    }

    pub fn findCompletions(self: *ConsoleApp, arena: std.mem.Allocator, prefix: []const u8) ![]const []const u8 {
        var matches = std.ArrayListUnmanaged([]const u8){};

        var builtin_iter = self.builder.commands.keyIterator();
        while (builtin_iter.next()) |key| {
            if (std.mem.startsWith(u8, key.*, prefix)) {
                try matches.append(arena, key.*);
            }
        }

        const outer_matches = try self.outer_shell.findCompletions(arena, prefix);
        for (outer_matches) |match| {
            var is_duplicate = false;
            for (matches.items) |existing| {
                if (std.mem.eql(u8, existing, match)) {
                    is_duplicate = true;
                    break;
                }
            }
            if (!is_duplicate) {
                try matches.append(arena, match);
            }
        }

        return matches.toOwnedSlice(arena);
    }

    fn updateSelection(self: *ConsoleApp, terminal: *Terminal, line: *std.ArrayList(u8), matches: []const []const u8, index: usize, display_len: *usize) !void {
        const match = matches[index];

        for (0..display_len.*) |_| {
            try terminal.backspace();
        }

        line.clearRetainingCapacity();
        try line.appendSlice(self.allocator, match);
        display_len.* = match.len;

        try terminal.print("{s}", .{match});
        try self.renderDropdown(terminal, matches, index);
        try terminal.flush();
    }

    fn renderDropdown(self: *ConsoleApp, terminal: *Terminal, matches: []const []const u8, selected: usize) !void {
        _ = self;
        try terminal.cursorSave();

        const max_display = @min(matches.len, 8);
        for (0..max_display) |i| {
            try terminal.print("\n", .{});
            try terminal.clearLine();
            if (i == selected) {
                try terminal.highlight(matches[i]);
            } else {
                try terminal.print("  {s}", .{matches[i]});
            }
        }

        if (matches.len > 8) {
            try terminal.print("\n", .{});
            try terminal.clearLine();
            try terminal.print("  ... and {d} more", .{matches.len - 8});
        }

        try terminal.cursorRestore();
    }

    fn clearDropdown(self: *ConsoleApp, terminal: *Terminal, count: usize) !void {
        _ = self;
        try terminal.cursorSave();

        const lines = @min(count, 8) + if (count > 8) @as(usize, 1) else @as(usize, 0);
        for (0..lines) |_| {
            try terminal.print("\n", .{});
            try terminal.clearLine();
        }

        try terminal.cursorRestore();
    }

    pub fn stop(self: *ConsoleApp) void {
        self.is_running = false;
    }
};

fn comptimeLower(comptime s: []const u8) *const [s.len]u8 {
    comptime {
        var buf: [s.len]u8 = undefined;
        _ = std.ascii.lowerString(&buf, s);
        const final = buf;
        return &final;
    }
}
