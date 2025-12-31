const std = @import("std");
const ansi = @import("utils/ansi.zig");
const directory = @import("modules/directory.zig");
const git = @import("modules/git.zig");
const nodejs = @import("modules/nodejs.zig");
const duration = @import("modules/duration.zig");
const config = @import("config.zig");

pub fn render(allocator: std.mem.Allocator, cfg: config.Config, exit_status: u8, duration_ms: u64) ![]u8 {
    var buffer: std.ArrayList(u8) = .{};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Get current directory
    const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch "/";
    defer allocator.free(cwd);

    // Directory
    if (!cfg.directory.disabled) {
        try directory.render(writer, allocator, cwd);
        try writer.writeAll(" ");
    }

    // Git (if in a repo and not disabled)
    if (!cfg.git_branch.disabled and !cfg.git_status.disabled) {
        if (try git.render(writer, allocator, cwd)) {
            try writer.writeAll(" ");
        }
    }

    // Node.js (if in a node project and not disabled)
    if (!cfg.nodejs.disabled) {
        if (try nodejs.render(writer, allocator, cwd)) {
            try writer.writeAll(" ");
        }
    }

    // Duration (if > min_time and not disabled)
    if (!cfg.cmd_duration.disabled) {
        if (try duration.renderWithConfig(writer, duration_ms, cfg.cmd_duration.min_time)) {
            try writer.writeAll(" ");
        }
    }

    // Newline before character
    try writer.writeAll("\n");

    // Exit status character (if not disabled)
    if (!cfg.character.disabled) {
        if (exit_status == 0) {
            try ansi.bold(writer, "→", ansi.success_color);
        } else {
            try ansi.bold(writer, "→", ansi.error_color);
        }
        try writer.writeAll(" ");
    }

    return buffer.toOwnedSlice(allocator);
}

test "render basic prompt" {
    const allocator = std.testing.allocator;
    const cfg = config.Config{};
    const result = try render(allocator, cfg, 0, 0);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
