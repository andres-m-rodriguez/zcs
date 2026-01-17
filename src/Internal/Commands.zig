const std = @import("std");
const outerShell = @import("OuterShell.zig");

pub const Handler = *const fn (commandContext: CommandContext) anyerror!void;
pub const CommandContext = struct {
    app: *ConsoleApp,
    output_writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    command_name: []const u8,
    args: []const u8,
    raw_input: []const u8,
};
pub const ConsoleAppBuilder = struct {
    commands: std.StringHashMapUnmanaged(Handler),
    output_writer: *std.Io.Writer = undefined,

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
    pub fn build(self: *ConsoleAppBuilder) ConsoleApp {
        return ConsoleApp{
            .app_builder = self,
            .is_running = false,
            .output_writer = self.output_writer,
        };
    }
    pub fn deinit(self: *ConsoleAppBuilder, allocator: std.mem.Allocator) void {
        self.commands.deinit(allocator);
    }
};

pub const ConsoleApp = struct {
    app_builder: *ConsoleAppBuilder,
    output_writer: *std.Io.Writer,

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
        };
        const builtin_handler = self.findBuiltInCommand(commandName);
        if (builtin_handler) |handler| {
            try handler(ctx);
            return;
        }

        const command_path = outerShell.findExecutable(allocator, commandName);
        if (command_path) |path| {
            try outerShell.executeCommandLine(allocator, path, commandName, args);
            return;
        }

        try handleNotFound(ctx);
    }

    pub fn run(self: *ConsoleApp) void {
        self.is_running = true;
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
