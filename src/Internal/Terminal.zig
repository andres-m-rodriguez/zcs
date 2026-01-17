const std = @import("std");
const builtin = @import("builtin");

pub const Terminal = struct {
    original_termios: if (builtin.os.tag != .windows) std.posix.termios else void,
    original_console_mode: if (builtin.os.tag == .windows) std.os.windows.DWORD else void,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stdout_buffer: [4096]u8 = undefined,
    stdout_writer: std.fs.File.Writer = undefined,

    pub fn init() !Terminal {
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();

        var term = Terminal{
            .original_termios = if (builtin.os.tag != .windows) undefined else {},
            .original_console_mode = if (builtin.os.tag == .windows) 0 else {},
            .stdin = stdin,
            .stdout = stdout,
        };

        term.stdout_writer = stdout.writerStreaming(&term.stdout_buffer);

        if (builtin.os.tag != .windows) {
            var termios = try std.posix.tcgetattr(stdin.handle);
            term.original_termios = termios;

            termios.lflag.ICANON = false;
            termios.lflag.ECHO = false;

            try std.posix.tcsetattr(stdin.handle, .FLUSH, termios);
        } else {
            const handle = stdin.handle;
            var original_mode: std.os.windows.DWORD = 0;
            _ = std.os.windows.kernel32.GetConsoleMode(handle, &original_mode);
            term.original_console_mode = original_mode;
            var mode = original_mode;
            mode &= ~@as(u32, 0x0002 | 0x0004);
            mode |= 0x0200;
            _ = std.os.windows.kernel32.SetConsoleMode(handle, mode);
        }

        return term;
    }

    pub fn deinit(self: *Terminal) void {
        if (builtin.os.tag != .windows) {
            std.posix.tcsetattr(self.stdin.handle, .FLUSH, self.original_termios) catch {};
        } else {
            _ = std.os.windows.kernel32.SetConsoleMode(self.stdin.handle, self.original_console_mode);
        }
    }

    pub fn readChar(self: *Terminal) !u8 {
        var buf: [1]u8 = undefined;
        _ = try self.stdin.read(&buf);
        return buf[0];
    }

    pub fn print(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try self.stdout_writer.interface.print(fmt, args);
    }

    pub fn flush(self: *Terminal) !void {
        try self.stdout_writer.interface.flush();
    }

    pub fn clear(self: *Terminal) !void {
        try self.print("\x1b[2J\x1b[H", .{});
        try self.flush();
    }

    pub fn cursorSave(self: *Terminal) !void {
        try self.print("\x1b[s", .{});
    }

    pub fn cursorRestore(self: *Terminal) !void {
        try self.print("\x1b[u", .{});
    }

    pub fn cursorUp(self: *Terminal, n: usize) !void {
        try self.print("\x1b[{d}A", .{n});
    }

    pub fn cursorDown(self: *Terminal, n: usize) !void {
        try self.print("\x1b[{d}B", .{n});
    }

    pub fn clearLine(self: *Terminal) !void {
        try self.print("\x1b[K", .{});
    }

    pub fn backspace(self: *Terminal) !void {
        try self.print("\x08 \x08", .{});
    }

    pub fn highlight(self: *Terminal, text: []const u8) !void {
        try self.print("\x1b[7m {s} \x1b[0m", .{text});
    }

    pub fn writer(self: *Terminal) *std.Io.Writer {
        return &self.stdout_writer.interface;
    }
};

pub const Key = union(enum) {
    char: u8,
    up,
    down,
    left,
    right,
    tab,
    enter,
    backspace,
    escape,
    unknown,

    pub fn read(terminal: *Terminal) !Key {
        const c = try terminal.readChar();

        return switch (c) {
            '\t' => .tab,
            '\n', '\r' => .enter,
            127, 8 => .backspace,
            27 => {
                const next = try terminal.readChar();
                if (next == '[') {
                    const code = try terminal.readChar();
                    return switch (code) {
                        'A' => .up,
                        'B' => .down,
                        'C' => .right,
                        'D' => .left,
                        else => .unknown,
                    };
                } else if (next == 27) {
                    return .escape;
                }
                return .unknown;
            },
            32...126 => .{ .char = c },
            else => .unknown,
        };
    }
};
