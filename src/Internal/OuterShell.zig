const std = @import("std");
const builtin = @import("builtin");

pub const OuterShell = struct {
    commands: std.StringHashMapUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !OuterShell {
        var shell = OuterShell{
            .commands = .{},
            .allocator = allocator,
        };
        try shell.cacheExecutables();
        return shell;
    }

    pub fn deinit(self: *OuterShell) void {
        var iter = self.commands.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.commands.deinit(self.allocator);
    }

    fn cacheExecutables(self: *OuterShell) !void {
        const path_env = std.process.getEnvVarOwned(self.allocator, "PATH") catch return;
        defer self.allocator.free(path_env);

        const separator = if (builtin.os.tag == .windows) ';' else ':';
        var path_iter = std.mem.splitScalar(u8, path_env, separator);

        while (path_iter.next()) |dir| {
            if (dir.len == 0) continue;
            if (!std.fs.path.isAbsolute(dir)) continue;
            var dir_handle = std.fs.openDirAbsolute(dir, .{ .iterate = true }) catch continue;
            defer dir_handle.close();

            var iter = dir_handle.iterate();
            while (try iter.next()) |entry| {
                if (entry.kind == .file) {
                    const cmd_name = if (builtin.os.tag == .windows) blk: {
                        const ext = std.fs.path.extension(entry.name);
                        if (ext.len == 0) break :blk entry.name;
                        if (std.ascii.eqlIgnoreCase(ext, ".exe") or
                            std.ascii.eqlIgnoreCase(ext, ".cmd") or
                            std.ascii.eqlIgnoreCase(ext, ".bat") or
                            std.ascii.eqlIgnoreCase(ext, ".com"))
                        {
                            break :blk entry.name[0 .. entry.name.len - ext.len];
                        }
                        continue;
                    } else entry.name;

                    if (self.commands.contains(cmd_name)) continue;

                    const name = self.allocator.dupe(u8, cmd_name) catch continue;

                    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const full_path = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{
                        dir,
                        std.fs.path.sep,
                        entry.name,
                    }) catch continue;

                    const path_copy = self.allocator.dupe(u8, full_path) catch continue;
                    self.commands.put(self.allocator, name, path_copy) catch continue;
                }
            }
        }
    }

    pub fn findExecutable(self: *OuterShell, command: []const u8) ?[]const u8 {
        const path_env = std.process.getEnvVarOwned(self.allocator, "PATH") catch return null;
        defer self.allocator.free(path_env);

        const separator = if (builtin.os.tag == .windows) ';' else ':';
        var path_iter = std.mem.splitScalar(u8, path_env, separator);

        while (path_iter.next()) |dir| {
            if (dir.len == 0) continue;
            if (!std.fs.path.isAbsolute(dir)) continue;

            var path_buf: [std.fs.max_path_bytes]u8 = undefined;

            if (builtin.os.tag == .windows) {
                const exts = [_][]const u8{ ".exe", ".cmd", ".bat", ".com" };
                for (exts) |ext| {
                    const full = std.fmt.bufPrint(&path_buf, "{s}{c}{s}{s}", .{ dir, std.fs.path.sep, command, ext }) catch continue;
                    if (std.fs.cwd().access(full, .{})) |_| {
                        return self.allocator.dupe(u8, full) catch return null;
                    } else |_| {}
                }
            } else {
                const full = std.fmt.bufPrint(&path_buf, "{s}{c}{s}", .{ dir, std.fs.path.sep, command }) catch continue;
                const file = std.fs.openFileAbsolute(full, .{}) catch continue;
                file.close();
                return self.allocator.dupe(u8, full) catch return null;
            }
        }
        return null;
    }

    pub fn findCompletions(self: *OuterShell, arena: std.mem.Allocator, prefix: []const u8) ![]const []const u8 {
        var matches = std.ArrayListUnmanaged([]const u8){};

        var iter = self.commands.keyIterator();
        while (iter.next()) |key| {
            if (std.mem.startsWith(u8, key.*, prefix)) {
                try matches.append(arena, key.*);
            }
        }

        return matches.toOwnedSlice(arena);
    }

    pub fn executeCommand(self: *OuterShell, commandName: []const u8, args: []const u8) !void {
        const path = self.findExecutable(commandName) orelse return error.CommandNotFound;

        var arg_list = std.ArrayListUnmanaged([]const u8){};
        defer arg_list.deinit(self.allocator);

        try arg_list.append(self.allocator, path);

        var args_it = std.mem.tokenizeScalar(u8, args, ' ');
        while (args_it.next()) |arg| {
            try arg_list.append(self.allocator, arg);
        }

        var child = std.process.Child.init(arg_list.items, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        _ = try child.spawnAndWait();
    }

    pub fn executeCommandParsed(self: *OuterShell, commandName: []const u8, args: []const []const u8) !void {
        _ = self.findExecutable(commandName) orelse return error.CommandNotFound;

        var arg_list = std.ArrayListUnmanaged([]const u8){};
        defer arg_list.deinit(self.allocator);

        try arg_list.append(self.allocator, commandName);

        for (args) |arg| {
            try arg_list.append(self.allocator, arg);
        }

        var child = std.process.Child.init(arg_list.items, self.allocator);
        child.stdin_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        _ = try child.spawnAndWait();
    }
};
