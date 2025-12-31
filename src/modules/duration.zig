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

    // Format duration
    if (duration_ms >= 60000) {
        // Minutes
        const minutes = duration_ms / 60000;
        const seconds = (duration_ms % 60000) / 1000;
        try ansi.bold(writer, "", ansi.duration_color);
        try writer.print("%{\x1b[1;33m%}{d}m {d}s%{\x1b[0m%}", .{ minutes, seconds });
    } else if (duration_ms >= 1000) {
        // Seconds
        const seconds = duration_ms / 1000;
        const ms = duration_ms % 1000;
        if (ms > 0) {
            try writer.print("%{{\x1b[1;33m%}}{d}.{d:0>3}s%{{\x1b[0m%}}", .{ seconds, ms });
        } else {
            try writer.print("%{{\x1b[1;33m%}}{d}s%{{\x1b[0m%}}", .{seconds});
        }
    } else {
        try writer.print("%{{\x1b[1;33m%}}{d}ms%{{\x1b[0m%}}", .{duration_ms});
    }

    return true;
}

test "duration formatting" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    // Duration below threshold should return false
    const result = try render(fbs.writer(), 1000);
    try std.testing.expect(!result);
}
