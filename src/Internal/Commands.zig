const std = @import("std");

const built_in_commands = .{ "echo", "exit", "type" };

pub const Handler = *const fn (commandContext: CommandContext) anyerror!void;
pub const CommandContext = struct {
    app: *ConsoleApp,
    output_writer: *std.Io.Writer,
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
    pub fn findBuiltInCommand(self: *ConsoleApp, commandName: [] const u8) ?Handler{
        var lower_buf: [256]u8 = undefined;
        const command_name_l = std.ascii.lowerString(lower_buf[0..commandName.len], commandName);

        const commandHandler = self.app_builder.commands.get(command_name_l) orelse return null;
        return commandHandler;
    }
    pub fn handleCommand(
        self: *ConsoleApp,
        commandName: []const u8,
        args: []const u8,
        rawInput: []const u8,
    ) !bool {

        const ctx = CommandContext{
            .app = self,
            .output_writer = self.output_writer,
            .command_name = commandName,
            .args = args,
            .raw_input = rawInput,
        };
        const commandHandler = self.findBuiltInCommand(commandName) orelse return false;
        try commandHandler(ctx);
        return true;
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
