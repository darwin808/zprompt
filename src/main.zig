const std = @import("std");
const ansi = @import("utils/ansi.zig");
const shell = @import("shell/zsh.zig");
const prompt = @import("prompt.zig");
const config = @import("config.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "init")) {
        try handleInit(args[2..]);
    } else if (std.mem.eql(u8, command, "prompt")) {
        try handlePrompt(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage();
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-V")) {
        try printVersion();
    } else {
        try printUsage();
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\zprompt - A minimal, fast shell prompt
        \\
        \\USAGE:
        \\    zprompt <COMMAND>
        \\
        \\COMMANDS:
        \\    init <SHELL>    Print shell init script (only 'zsh' supported)
        \\    prompt          Print the prompt
        \\    help            Show this help message
        \\    version         Show version
        \\
        \\EXAMPLES:
        \\    eval "$(zprompt init zsh)"
        \\
    );
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("zprompt 0.1.0\n");
}

fn handleInit(args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    if (args.len == 0) {
        try stdout.writeAll("Error: missing shell argument. Use: zprompt init zsh\n");
        return;
    }

    const shell_name = args[0];
    if (std.mem.eql(u8, shell_name, "zsh")) {
        try stdout.writeAll(shell.zsh_init_script);
    } else {
        try stdout.print("Error: unsupported shell '{s}'. Only 'zsh' is supported.\n", .{shell_name});
    }
}

fn handlePrompt(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Load configuration
    const cfg = config.load(allocator) catch config.Config{};

    // Parse arguments for status code and duration
    var status: u8 = 0;
    var duration_ms: u64 = 0;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--status") and i + 1 < args.len) {
            status = std.fmt.parseInt(u8, args[i + 1], 10) catch 0;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--cmd-duration") and i + 1 < args.len) {
            duration_ms = std.fmt.parseInt(u64, args[i + 1], 10) catch 0;
            i += 1;
        }
    }

    const prompt_str = try prompt.render(allocator, cfg, status, duration_ms);
    defer allocator.free(prompt_str);

    try stdout.writeAll(prompt_str);
}

test "basic test" {
    // Basic sanity test
    try std.testing.expect(true);
}
