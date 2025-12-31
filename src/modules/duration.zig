const std = @import("std");
const ansi = @import("../utils/ansi.zig");

// Default minimum duration to display (in milliseconds)
const default_min_duration_ms: u64 = 2000;

pub fn render(writer: anytype, duration_ms: u64) !bool {
    return renderWithConfig(writer, duration_ms, default_min_duration_ms);
}

pub fn renderWithConfig(writer: anytype, duration_ms: u64, min_duration_ms: u64) !bool {
    if (duration_ms < min_duration_ms) {
        return false;
    }

    try ansi.fg(writer, "took ", ansi.duration_color);

    // Format duration - write directly without complex formatting
    if (duration_ms >= 60000) {
        // Minutes
        const minutes = duration_ms / 60000;
        const seconds = (duration_ms % 60000) / 1000;
        try ansi.bold(writer, "", ansi.duration_color);
        // Write the time value
        var buf: [32]u8 = undefined;
        const time_str = std.fmt.bufPrint(&buf, "{d}m {d}s", .{ minutes, seconds }) catch "?";
        try ansi.bold(writer, time_str, ansi.duration_color);
    } else if (duration_ms >= 1000) {
        // Seconds
        const seconds = duration_ms / 1000;
        const ms = duration_ms % 1000;
        var buf: [32]u8 = undefined;
        const time_str = if (ms > 0)
            std.fmt.bufPrint(&buf, "{d}.{d:0>3}s", .{ seconds, ms }) catch "?"
        else
            std.fmt.bufPrint(&buf, "{d}s", .{seconds}) catch "?";
        try ansi.bold(writer, time_str, ansi.duration_color);
    } else {
        var buf: [32]u8 = undefined;
        const time_str = std.fmt.bufPrint(&buf, "{d}ms", .{duration_ms}) catch "?";
        try ansi.bold(writer, time_str, ansi.duration_color);
    }

    return true;
}

test "duration formatting" {
    // Basic placeholder test
    try std.testing.expect(true);
}
