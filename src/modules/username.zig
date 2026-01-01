const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const UsernameInfo = struct {
    username: []const u8,
};

/// Get username
pub fn detect(allocator: std.mem.Allocator) ?UsernameInfo {
    return getUsernameInfo(allocator) catch null;
}

/// Render username info
pub fn renderFromInfo(writer: anytype, info: UsernameInfo) !bool {
    try ansi.bold(writer, info.username, ansi.username_color);
    return true;
}

/// Convenience wrapper
pub fn render(writer: anytype, allocator: std.mem.Allocator) !bool {
    const info = detect(allocator) orelse return false;
    // username is not allocated, don't need to free
    return try renderFromInfo(writer, info);
}

fn getUsernameInfo(allocator: std.mem.Allocator) !UsernameInfo {
    _ = allocator;

    // Get from environment variable
    const username = std.posix.getenv("USER") orelse
        std.posix.getenv("LOGNAME") orelse
        return error.NoUsername;

    return UsernameInfo{
        .username = username,
    };
}

test "username detection" {
    const allocator = std.testing.allocator;
    if (detect(allocator)) |info| {
        try std.testing.expect(info.username.len > 0);
    }
}
