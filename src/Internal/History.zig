const std = @import("std");

pub const History = struct {
    entries: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,
    index: usize,
    max_entries: usize,

    pub fn init(allocator: std.mem.Allocator) History {
        return .{
            .entries = .{},
            .allocator = allocator,
            .index = 0,
            .max_entries = 1000,
        };
    }

    pub fn load(allocator: std.mem.Allocator) !History {
        var self = init(allocator);

        const path = try getHistoryPath(allocator);
        defer allocator.free(path);

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                return self;
            }
            return err;
        };
        defer file.close();

        const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
            if (err == error.EndOfStream) {
                return self;
            }
            return err;
        };
        defer allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len > 0) {
                const entry = try allocator.dupe(u8, line);
                try self.entries.append(allocator, entry);
            }
        }

        self.index = self.entries.items.len;
        return self;
    }

    pub fn save(self: *History) !void {
        const path = try getHistoryPath(self.allocator);
        defer self.allocator.free(path);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        var writer = file.writerStreaming(&buf);

        const start = if (self.entries.items.len > self.max_entries)
            self.entries.items.len - self.max_entries
        else
            0;

        for (self.entries.items[start..]) |entry| {
            try writer.interface.writeAll(entry);
            try writer.interface.writeAll("\n");
        }
        try writer.interface.flush();
    }

    pub fn add(self: *History, command: []const u8) !void {
        if (command.len == 0) return;

        // Don't add duplicates of the last entry
        if (self.entries.items.len > 0) {
            const last = self.entries.items[self.entries.items.len - 1];
            if (std.mem.eql(u8, last, command)) {
                self.index = self.entries.items.len;
                return;
            }
        }

        const entry = try self.allocator.dupe(u8, command);
        try self.entries.append(self.allocator, entry);
        self.index = self.entries.items.len;
    }

    pub fn up(self: *History) ?[]const u8 {
        if (self.entries.items.len == 0) return null;
        if (self.index > 0) {
            self.index -= 1;
        }
        return self.entries.items[self.index];
    }

    pub fn down(self: *History) ?[]const u8 {
        if (self.entries.items.len == 0) return null;
        if (self.index < self.entries.items.len - 1) {
            self.index += 1;
            return self.entries.items[self.index];
        } else {
            self.index = self.entries.items.len;
            return null; // Return null to clear line (new command)
        }
    }

    pub fn resetIndex(self: *History) void {
        self.index = self.entries.items.len;
    }

    pub fn deinit(self: *History) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry);
        }
        self.entries.deinit(self.allocator);
    }
};

fn getHistoryPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch |err| {
        if (err == error.EnvironmentVariableNotFound) {
            return std.process.getEnvVarOwned(allocator, "HOME") catch {
                return error.HomeNotFound;
            };
        }
        return err;
    };
    defer allocator.free(home);

    return std.fmt.allocPrint(allocator, "{s}\\.zcs_history", .{home});
}
