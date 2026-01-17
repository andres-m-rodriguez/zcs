const std = @import("std");
const console = @import("./Internal/Commands.zig");
const builtinCommands = @import("Internal/BuiltinCommands.zig");
const OuterShell = @import("Internal/OuterShell.zig").OuterShell;
const Terminal = @import("Internal/Terminal.zig").Terminal;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var terminal = try Terminal.init();
    defer terminal.deinit();

    var outer_shell = try OuterShell.init(allocator);
    defer outer_shell.deinit();

    var buffer: [4092]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&buffer);
    const stdout = &stdout_writer.interface;

    var app_builder = console.ConsoleAppBuilder{ .commands = .{} };
    defer app_builder.deinit(allocator);
    try builtinCommands.registerBuiltInCommands(&app_builder, allocator);
    app_builder.addWriter(stdout);
    app_builder.addOuterShell(&outer_shell);
    var app = app_builder.build();
    app.run();

    var line = std.ArrayList(u8){};
    defer line.deinit(allocator);

    var tab_index: usize = 0;
    var current_matches: []const []const u8 = &.{};
    var completion_arena = std.heap.ArenaAllocator.init(allocator);
    defer completion_arena.deinit();
    var original_prefix: []const u8 = &.{};
    var display_len: usize = 0;
    var dropdown_open = false;

    try stdout.print("$ ", .{});
    try stdout.flush();

    while (app.is_running) {
        const char = try terminal.readChar();

        if (char == '\n' or char == '\r') {
            if (dropdown_open) {
                try clearDropdown(stdout, current_matches.len);
                dropdown_open = false;
            }

            try stdout.print("\n", .{});
            try stdout.flush();

            if (line.items.len > 0) {
                const input = line.items;
                var iter = std.mem.tokenizeScalar(u8, input, ' ');
                const command_name = iter.next() orelse "";
                const args_start = if (command_name.len < input.len) command_name.len + 1 else command_name.len;
                const args = if (args_start < input.len) input[args_start..] else "";

                try app.handleCommand(allocator, command_name, args, input);
                try stdout.flush();
            }

            line.clearRetainingCapacity();
            tab_index = 0;
            current_matches = &.{};
            _ = completion_arena.reset(.retain_capacity);
            original_prefix = &.{};
            display_len = 0;

            if (app.is_running) {
                try stdout.print("$ ", .{});
                try stdout.flush();
            }
        } else if (char == '\t') {
            if (current_matches.len == 0) {
                _ = completion_arena.reset(.retain_capacity);
                original_prefix = try completion_arena.allocator().dupe(u8, line.items);
                current_matches = try app.findCompletions(completion_arena.allocator(), original_prefix);
                tab_index = 0;
                display_len = line.items.len;
            }

            if (current_matches.len > 0) {
                if (tab_index >= current_matches.len) {
                    tab_index = 0;
                }
                const match = current_matches[tab_index];

                for (0..display_len) |_| {
                    try stdout.print("\x08 \x08", .{});
                }

                line.clearRetainingCapacity();
                try line.appendSlice(allocator, match);
                display_len = match.len;

                try stdout.print("{s}", .{match});

                if (current_matches.len > 1) {
                    try renderDropdown(stdout, current_matches, tab_index);
                    dropdown_open = true;
                }

                try stdout.flush();
                tab_index += 1;
            }
        } else if (char == 27) {
            const next = try terminal.readChar();
            if (next == '[') {
                const code = try terminal.readChar();
                if (dropdown_open and current_matches.len > 0) {
                    if (code == 'A') {
                        if (tab_index == 0) {
                            tab_index = current_matches.len - 1;
                        } else {
                            tab_index -= 1;
                        }
                        const match = current_matches[tab_index];

                        for (0..display_len) |_| {
                            try stdout.print("\x08 \x08", .{});
                        }

                        line.clearRetainingCapacity();
                        try line.appendSlice(allocator, match);
                        display_len = match.len;

                        try stdout.print("{s}", .{match});
                        try renderDropdown(stdout, current_matches, tab_index);
                        try stdout.flush();
                    } else if (code == 'B') {
                        tab_index += 1;
                        if (tab_index >= current_matches.len) {
                            tab_index = 0;
                        }
                        const match = current_matches[tab_index];

                        for (0..display_len) |_| {
                            try stdout.print("\x08 \x08", .{});
                        }

                        line.clearRetainingCapacity();
                        try line.appendSlice(allocator, match);
                        display_len = match.len;

                        try stdout.print("{s}", .{match});
                        try renderDropdown(stdout, current_matches, tab_index);
                        try stdout.flush();
                    }
                }
            } else if (next == 27 or dropdown_open) {
                if (dropdown_open) {
                    try clearDropdown(stdout, current_matches.len);
                    dropdown_open = false;
                    current_matches = &.{};
                    tab_index = 0;
                    try stdout.flush();
                }
            }
        } else if (char == 127 or char == 8) {
            if (dropdown_open) {
                try clearDropdown(stdout, current_matches.len);
                dropdown_open = false;
            }
            if (line.items.len > 0) {
                _ = line.pop();
                try stdout.print("\x08 \x08", .{});
                try stdout.flush();
                display_len = line.items.len;
            }
            tab_index = 0;
            current_matches = &.{};
        } else if (char >= 32 and char < 127) {
            if (dropdown_open) {
                try clearDropdown(stdout, current_matches.len);
                dropdown_open = false;
            }
            try line.append(allocator, char);
            try stdout.print("{c}", .{char});
            try stdout.flush();
            display_len = line.items.len;
            tab_index = 0;
            current_matches = &.{};
        } else {
            tab_index = 0;
            current_matches = &.{};
        }
    }
}

fn renderDropdown(stdout: *std.Io.Writer, matches: []const []const u8, selected: usize) !void {
    try stdout.print("\x1b[s", .{});

    const max_display = @min(matches.len, 8);
    for (0..max_display) |i| {
        try stdout.print("\n\x1b[K", .{});
        if (i == selected) {
            try stdout.print("\x1b[7m {s} \x1b[0m", .{matches[i]});
        } else {
            try stdout.print("  {s}", .{matches[i]});
        }
    }

    if (matches.len > 8) {
        try stdout.print("\n\x1b[K  ... and {d} more", .{matches.len - 8});
    }

    try stdout.print("\x1b[u", .{});
}

fn clearDropdown(stdout: *std.Io.Writer, count: usize) !void {
    try stdout.print("\x1b[s", .{});

    const lines_to_clear = @min(count, 8) + if (count > 8) @as(usize, 1) else @as(usize, 0);
    for (0..lines_to_clear) |_| {
        try stdout.print("\n\x1b[K", .{});
    }

    try stdout.print("\x1b[u", .{});
}
