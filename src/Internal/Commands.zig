const std = @import("std");
const OuterShell = @import("OuterShell.zig").OuterShell;

pub const Handler = *const fn (commandContext: CommandContext) anyerror!void;
pub const CommandContext = struct {
    app: *ConsoleApp,
    output_writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    command_name: []const u8,
    args: []const u8,
    raw_input: []const u8,
    outer_shell: *OuterShell,
};
pub const ConsoleAppBuilder = struct {
    commands: std.StringHashMapUnmanaged(Handler),
    output_writer: *std.Io.Writer = undefined,
    outer_shell: *OuterShell = undefined,

    pub fn addCommand(
        self: *ConsoleAppBuilder,
        allocator: std.mem.Allocator,
        comptime commandName: []const u8,
        commandHandler: Handler,
    ) !void {
        const command_name_l = comptime comptimeLower(commandName);
        try self.commands.put(allocator, command_name_l, commandHandler);
    }
    pub fn addWriter(self: *ConsoleAppBuilder, writer: *std.Io.Writer) void {
        self.output_writer = writer;
    }
    pub fn addOuterShell(self: *ConsoleAppBuilder, shell: *OuterShell) void {
        self.outer_shell = shell;
    }
    pub fn build(self: *ConsoleAppBuilder) ConsoleApp {
        return ConsoleApp{
            .app_builder = self,
            .is_running = false,
            .output_writer = self.output_writer,
            .outer_shell = self.outer_shell,
        };
    }
    pub fn deinit(self: *ConsoleAppBuilder, allocator: std.mem.Allocator) void {
        self.commands.deinit(allocator);
    }
};

pub const ConsoleApp = struct {
    app_builder: *ConsoleAppBuilder,
    output_writer: *std.Io.Writer,
    outer_shell: *OuterShell,

    is_running: bool,
    pub fn findBuiltInCommand(self: *ConsoleApp, commandName: []const u8) ?Handler {
        var lower_buf: [256]u8 = undefined;
        const command_name_l = std.ascii.lowerString(lower_buf[0..commandName.len], commandName);

        const commandHandler = self.app_builder.commands.get(command_name_l) orelse return null;
        return commandHandler;
    }

    pub fn handleCommand(
        self: *ConsoleApp,
        allocator: std.mem.Allocator,
        commandName: []const u8,
        args: []const u8,
        rawInput: []const u8,
    ) !void {
        const ctx = CommandContext{
            .app = self,
            .output_writer = self.output_writer,
            .allocator = allocator,
            .command_name = commandName,
            .args = args,
            .raw_input = rawInput,
            .outer_shell = self.outer_shell,
        };
        const builtin_handler = self.findBuiltInCommand(commandName);
        if (builtin_handler) |handler| {
            try handler(ctx);
            return;
        }

        const command_path = self.outer_shell.findExecutable(commandName);
        if (command_path) |_| {
            try self.outer_shell.executeCommand(commandName, args);
            return;
        }

        try handleNotFound(ctx);
    }

    pub fn run(self: *ConsoleApp) void {
        self.is_running = true;
    }

    pub fn findCompletions(self: *ConsoleApp, arena: std.mem.Allocator, prefix: []const u8) ![]const []const u8 {
        var matches = std.ArrayListUnmanaged([]const u8){};

        var builtin_iter = self.app_builder.commands.keyIterator();
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
};

fn comptimeLower(comptime s: []const u8) *const [s.len]u8 {
    comptime {
        var buf: [s.len]u8 = undefined;
        _ = std.ascii.lowerString(&buf, s);
        const final = buf; //needs copying
        return &final;
    }
}
pub fn handleNotFound(ctx: CommandContext) !void {
    try ctx.output_writer.print("{s}: command not found\n", .{ctx.command_name});
}
