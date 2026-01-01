const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const HostnameInfo = struct {
    hostname: []const u8,
    is_ssh: bool = false,
};

/// Get hostname info
pub fn detect(allocator: std.mem.Allocator) ?HostnameInfo {
    return getHostnameInfo(allocator) catch null;
}

/// Render hostname info
pub fn renderFromInfo(writer: anytype, info: HostnameInfo) !bool {
    // Show @ separator if rendering after username
    try ansi.fg(writer, "@", ansi.muted_color);
    try ansi.bold(writer, info.hostname, ansi.hostname_color);
    return true;
}

/// Convenience wrapper
pub fn render(writer: anytype, allocator: std.mem.Allocator) !bool {
    const info = detect(allocator) orelse return false;
    defer allocator.free(info.hostname);
    return try renderFromInfo(writer, info);
}

fn getHostnameInfo(allocator: std.mem.Allocator) !HostnameInfo {
    // Check if in SSH session
    const is_ssh = std.posix.getenv("SSH_CONNECTION") != null or
        std.posix.getenv("SSH_CLIENT") != null or
        std.posix.getenv("SSH_TTY") != null;

    // Try hostname from environment first
    if (std.posix.getenv("HOSTNAME")) |hostname| {
        return HostnameInfo{
            .hostname = try allocator.dupe(u8, hostname),
            .is_ssh = is_ssh,
        };
    }

    // Read from /etc/hostname
    const hostname_content = std.fs.cwd().readFileAlloc(allocator, "/etc/hostname", 256) catch {
        // Fall back to "localhost"
        return HostnameInfo{
            .hostname = try allocator.dupe(u8, "localhost"),
            .is_ssh = is_ssh,
        };
    };
    defer allocator.free(hostname_content);

    const trimmed = std.mem.trim(u8, hostname_content, " \t\n\r");

    return HostnameInfo{
        .hostname = try allocator.dupe(u8, trimmed),
        .is_ssh = is_ssh,
    };
}

test "hostname detection" {
    const allocator = std.testing.allocator;
    if (detect(allocator)) |info| {
        defer allocator.free(info.hostname);
        try std.testing.expect(info.hostname.len > 0);
    }
}
