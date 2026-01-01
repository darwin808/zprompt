const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const TimeInfo = struct {
    time_str: []const u8,
};

/// Get current time
pub fn detect(allocator: std.mem.Allocator) ?TimeInfo {
    return getTimeInfo(allocator) catch null;
}

/// Render time info
pub fn renderFromInfo(writer: anytype, info: TimeInfo) !bool {
    try ansi.fg(writer, "at ", ansi.muted_color);
    try ansi.bold(writer, "🕐 ", ansi.time_color);
    try ansi.fg(writer, info.time_str, ansi.time_color);
    return true;
}

/// Convenience wrapper
pub fn render(writer: anytype, allocator: std.mem.Allocator) !bool {
    const info = detect(allocator) orelse return false;
    defer allocator.free(info.time_str);
    return try renderFromInfo(writer, info);
}

fn getTimeInfo(allocator: std.mem.Allocator) !TimeInfo {
    const timestamp = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const day_seconds = epoch_seconds.getDaySeconds();

    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    var buf: [16]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ hour, minute, second }) catch return error.FormatFailed;

    return TimeInfo{
        .time_str = try allocator.dupe(u8, buf[0..len.len]),
    };
}

test "time detection" {
    const allocator = std.testing.allocator;
    if (detect(allocator)) |info| {
        defer allocator.free(info.time_str);
        try std.testing.expect(info.time_str.len > 0);
    }
}
