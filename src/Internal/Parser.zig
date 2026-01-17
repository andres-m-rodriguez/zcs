const std = @import("std");

pub const ParsedCommand = struct {
    executable: []const u8,
    args: []const []const u8,

    pub fn deinit(self: *ParsedCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.executable);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
    }
};

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !ParsedCommand {
    var tokens = std.ArrayList([]const u8){};
    defer tokens.deinit(allocator);

    var current = std.ArrayList(u8){};
    defer current.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        if (c == '\'') {
            i += 1;
            while (i < input.len and input[i] != '\'') {
                try current.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) i += 1;
        } else if (c == '"') {
            i += 1;
            while (i < input.len and input[i] != '"') {
                if (input[i] == '\\' and i + 1 < input.len) {
                    const next = input[i + 1];
                    if (next == '"' or next == '\\' or next == '$' or next == '`') {
                        try current.append(allocator, next);
                        i += 2;
                        continue;
                    }
                }
                try current.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) i += 1;
        } else if (c == '\\' and i + 1 < input.len) {
            try current.append(allocator, input[i + 1]);
            i += 2;
        } else if (c == ' ' or c == '\t') {
            if (current.items.len > 0) {
                const token = try allocator.dupe(u8, current.items);
                try tokens.append(allocator, token);
                current.clearRetainingCapacity();
            }
            while (i < input.len and (input[i] == ' ' or input[i] == '\t')) {
                i += 1;
            }
        } else {
            try current.append(allocator, c);
            i += 1;
        }
    }

    if (current.items.len > 0) {
        const token = try allocator.dupe(u8, current.items);
        try tokens.append(allocator, token);
    }

    if (tokens.items.len == 0) {
        return ParsedCommand{
            .executable = try allocator.dupe(u8, ""),
            .args = try allocator.alloc([]const u8, 0),
        };
    }

    const executable = tokens.items[0];
    const args = try allocator.dupe([]const u8, tokens.items[1..]);

    return ParsedCommand{
        .executable = executable,
        .args = args,
    };
}

pub fn parseArgs(allocator: std.mem.Allocator, input: []const u8) ![]const []const u8 {
    var tokens = std.ArrayList([]const u8){};
    defer tokens.deinit(allocator);

    var current = std.ArrayList(u8){};
    defer current.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];

        if (c == '\'') {
            i += 1;
            while (i < input.len and input[i] != '\'') {
                try current.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) i += 1;
        } else if (c == '"') {
            i += 1;
            while (i < input.len and input[i] != '"') {
                if (input[i] == '\\' and i + 1 < input.len) {
                    const next = input[i + 1];
                    if (next == '"' or next == '\\' or next == '$' or next == '`') {
                        try current.append(allocator, next);
                        i += 2;
                        continue;
                    }
                }
                try current.append(allocator, input[i]);
                i += 1;
            }
            if (i < input.len) i += 1;
        } else if (c == '\\' and i + 1 < input.len) {
            try current.append(allocator, input[i + 1]);
            i += 2;
        } else if (c == ' ' or c == '\t') {
            if (current.items.len > 0) {
                const token = try allocator.dupe(u8, current.items);
                try tokens.append(allocator, token);
                current.clearRetainingCapacity();
            }
            while (i < input.len and (input[i] == ' ' or input[i] == '\t')) {
                i += 1;
            }
        } else {
            try current.append(allocator, c);
            i += 1;
        }
    }

    if (current.items.len > 0) {
        const token = try allocator.dupe(u8, current.items);
        try tokens.append(allocator, token);
    }

    return try allocator.dupe([]const u8, tokens.items);
}

pub fn freeArgs(allocator: std.mem.Allocator, args: []const []const u8) void {
    for (args) |arg| {
        allocator.free(arg);
    }
    allocator.free(args);
}
