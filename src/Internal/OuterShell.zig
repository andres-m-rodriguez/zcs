const std = @import("std");
const builtin = @import("builtin");


pub fn findExecutable(allocator: std.mem.Allocator, command: []const u8) ?[]const u8 {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch return null;
    defer allocator.free(path_env);

    const separator = if (builtin.os.tag == .windows) ';' else ':';
    var path_iter = std.mem.splitScalar(u8, path_env, separator);

    // On Windows, try with .exe extension
    const extensions: []const []const u8 = if (builtin.os.tag == .windows)
        &.{ ".exe", ".cmd", ".bat", "" }
    else
        &.{""};

    while (path_iter.next()) |dir| {
        for (extensions) |ext| {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const full_path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}{s}", .{
                dir,
                std.fs.path.sep,
                command,
                ext,
            }) catch continue;

            const file = std.fs.openFileAbsolute(full_path, .{}) catch continue;
            defer file.close();

            if (builtin.os.tag != .windows) {
                const stat = file.stat() catch continue;
                const is_executable = (stat.mode & std.posix.S.IXUSR) != 0;
                if (!is_executable) continue;
            }

            return allocator.dupe(u8, full_path) catch return null;
        }
    }

    return null;
}

pub fn executeCommandLine(allocator:std.mem.Allocator, command: []const u8, commandName:[]const u8, args:[] const u8) !void {
    var arg_list = std.ArrayList([]const u8) {};
    defer arg_list.deinit(allocator);
_ = command;
    try arg_list.append(allocator, commandName);
    var args_it = std.mem.tokenizeScalar(u8, args, ' ');
    while(args_it.next()) |arg|{
        try arg_list.append(allocator, arg);
    }

    var proccess = std.process.Child.init(arg_list.items, allocator);
    
    _ = try proccess.spawnAndWait();
}
