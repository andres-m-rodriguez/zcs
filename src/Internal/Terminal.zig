const std = @import("std");
const builtin = @import("builtin");

pub const Terminal = struct {
    original_termios: if (builtin.os.tag != .windows) std.posix.termios else void,
    original_console_mode: if (builtin.os.tag == .windows) std.os.windows.DWORD else void,
    stdin: std.fs.File,

    pub fn init() !Terminal {
        const stdin = std.fs.File.stdin();
        if (builtin.os.tag != .windows) {
            var termios = try std.posix.tcgetattr(stdin.handle);
            const original = termios;

            termios.lflag.ICANON = false;
            termios.lflag.ECHO = false;

            try std.posix.tcsetattr(stdin.handle, .FLUSH, termios);

            return .{ .original_termios = original, .original_console_mode = {}, .stdin = stdin };
        } else {
            const handle = stdin.handle;
            var original_mode: std.os.windows.DWORD = 0;
            _ = std.os.windows.kernel32.GetConsoleMode(handle, &original_mode);
            var mode = original_mode;
            mode &= ~@as(u32, 0x0002 | 0x0004);
            mode |= 0x0200;
            _ = std.os.windows.kernel32.SetConsoleMode(handle, mode);
            return .{ .original_termios = {}, .original_console_mode = original_mode, .stdin = stdin };
        }
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
};
