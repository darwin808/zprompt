const std = @import("std");
const ansi = @import("utils/ansi.zig");
const zsh = @import("shell/zsh.zig");
const bash = @import("shell/bash.zig");
const fish = @import("shell/fish.zig");
const powershell = @import("shell/powershell.zig");
const prompt = @import("prompt.zig");
const config = @import("config.zig");

// Simple stdout write helper for Zig 0.15 compatibility
fn stdout_write(data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        written += try std.posix.write(std.posix.STDOUT_FILENO, data[written..]);
    }
}

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
    try stdout_write(
        \\zprompt - A minimal, fast shell prompt
        \\
        \\USAGE:
        \\    zprompt <COMMAND>
        \\
        \\COMMANDS:
        \\    init <SHELL>    Print shell init script
        \\    prompt          Print the prompt
        \\    help            Show this help message
        \\    version         Show version
        \\
        \\SUPPORTED SHELLS:
        \\    bash, zsh, fish, powershell
        \\
        \\EXAMPLES:
        \\    eval "$(zprompt init zsh)"
        \\    eval "$(zprompt init bash)"
        \\    zprompt init fish | source
        \\    Invoke-Expression (&zprompt init powershell)
        \\
    );
}

fn printVersion() !void {
    try stdout_write("zprompt 0.1.0\n");
}

fn handleInit(args: []const []const u8) !void {
    if (args.len == 0) {
        try stdout_write("Error: missing shell argument. Use: zprompt init <shell>\n");
        try stdout_write("Supported shells: bash, zsh, fish, powershell\n");
        return;
    }

    const shell_name = args[0];
    if (std.mem.eql(u8, shell_name, "zsh")) {
        try stdout_write(zsh.zsh_init_script);
    } else if (std.mem.eql(u8, shell_name, "bash")) {
        try stdout_write(bash.bash_init_script);
    } else if (std.mem.eql(u8, shell_name, "fish")) {
        try stdout_write(fish.fish_init_script);
    } else if (std.mem.eql(u8, shell_name, "powershell") or std.mem.eql(u8, shell_name, "pwsh")) {
        try stdout_write(powershell.powershell_init_script);
    } else {
        try stdout_write("Error: unsupported shell '");
        try stdout_write(shell_name);
        try stdout_write("'\nSupported shells: bash, zsh, fish, powershell\n");
    }
}

fn handlePrompt(parent_allocator: std.mem.Allocator, args: []const []const u8) !void {
    // Use arena allocator for all prompt-related allocations
    // Single bulk deallocation instead of many small frees
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

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

    // Render prompt - result allocated with parent_allocator for thread safety
    const prompt_str = try prompt.render(parent_allocator, allocator, cfg, status, duration_ms);
    defer parent_allocator.free(prompt_str);

    try stdout_write(prompt_str);
}

test "basic test" {
    try std.testing.expect(true);
}
