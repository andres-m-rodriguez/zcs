const std = @import("std");

pub const Bookmarks = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn load(allocator: std.mem.Allocator) !Bookmarks {
        var self = Bookmarks{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };

        const path = try getBookmarksPath(allocator);
        defer allocator.free(path);

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return self;
            }
            return err;
        };
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
            if (err == error.EndOfStream) {
                return self;
            }
            return err;
        };
        defer allocator.free(content);

        if (content.len == 0) {
            return self;
        }

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
            return self;
        };
        defer parsed.deinit();

        if (parsed.value != .object) {
            return self;
        }

        var iter = parsed.value.object.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* == .string) {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const value = try allocator.dupe(u8, entry.value_ptr.string);
                try self.map.put(key, value);
            }
        }

        return self;
    }

    pub fn save(self: *Bookmarks) !void {
        const path = try getBookmarksPath(self.allocator);
        defer self.allocator.free(path);

        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.fs.makeDirAbsolute(dir_path) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        var writer = file.writerStreaming(&buf);
        try writer.interface.writeAll("{");

        var first = true;
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            if (!first) {
                try writer.interface.writeAll(",");
            }
            first = false;
            try writer.interface.writeAll("\n  \"");
            try writer.interface.writeAll(entry.key_ptr.*);
            try writer.interface.writeAll("\": \"");
            for (entry.value_ptr.*) |c| {
                if (c == '\\') {
                    try writer.interface.writeAll("\\\\");
                } else if (c == '"') {
                    try writer.interface.writeAll("\\\"");
                } else {
                    try writer.interface.writeByte(c);
                }
            }
            try writer.interface.writeAll("\"");
        }

        if (!first) {
            try writer.interface.writeAll("\n");
        }
        try writer.interface.writeAll("}\n");
        try writer.interface.flush();
    }

    pub fn add(self: *Bookmarks, name: []const u8, path: []const u8) !void {
        if (self.map.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
        }
        const name_copy = try self.allocator.dupe(u8, name);
        const path_copy = try self.allocator.dupe(u8, path);
        try self.map.put(name_copy, path_copy);
    }

    pub fn remove(self: *Bookmarks, name: []const u8) bool {
        if (self.map.fetchRemove(name)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }

    pub fn get(self: *Bookmarks, name: []const u8) ?[]const u8 {
        return self.map.get(name);
    }

    pub fn deinit(self: *Bookmarks) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }
};

fn getBookmarksPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return std.process.getEnvVarOwned(allocator, "HOME") catch {
                return error.HomeNotFound;
            };
        }
        return err;
    };
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}\\.zcs_bookmarks.json", .{home});
}
