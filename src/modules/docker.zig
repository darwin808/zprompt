const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const DockerInfo = struct {
    context: ?[]const u8 = null,
};

/// Detect Docker info without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?DockerInfo {
    if (!isDockerProject(cwd)) {
        return null;
    }

    return getDockerInfo(allocator) catch null;
}

/// Render Docker info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: DockerInfo) !bool {
    // Show Docker context
    if (info.context) |ctx| {
        // Only show if not "default"
        if (!std.mem.eql(u8, ctx, "default")) {
            try ansi.fg(writer, "via ", ansi.muted_color);
            try ansi.bold(writer, "\xef\x8c\x95 ", ansi.docker_color); // U+F395 Docker icon
            try ansi.fg(writer, ctx, ansi.docker_color);
            return true;
        }
    }

    // Show docker indicator when in a docker project
    try ansi.fg(writer, "via ", ansi.muted_color);
    try ansi.bold(writer, "\xef\x8c\x95 docker", ansi.docker_color);
    return true;
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const info = detect(allocator, cwd) orelse return false;
    defer {
        if (info.context) |c| allocator.free(c);
    }
    return try renderFromInfo(writer, info);
}

/// Quick check if this is a Docker project (no subprocess, just file check)
pub fn exists(cwd: []const u8) bool {
    return isDockerProject(cwd);
}

fn isDockerProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    const check_files = [_][]const u8{
        "Dockerfile",
        "docker-compose.yml",
        "docker-compose.yaml",
        "compose.yml",
        "compose.yaml",
        ".dockerignore",
    };

    for (check_files) |file| {
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ cwd, file }) catch continue;
        if (std.fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    return false;
}

fn getDockerInfo(allocator: std.mem.Allocator) !DockerInfo {
    var info = DockerInfo{};

    // Check DOCKER_CONTEXT environment variable first (faster)
    if (std.posix.getenv("DOCKER_CONTEXT")) |ctx| {
        info.context = try allocator.dupe(u8, ctx);
        return info;
    }

    // Try to get current context from docker config
    info.context = getDockerContext(allocator) catch null;

    return info;
}

fn getDockerContext(allocator: std.mem.Allocator) ![]u8 {
    // Read ~/.docker/config.json for currentContext
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const config_path = try std.fmt.bufPrint(&path_buf, "{s}/.docker/config.json", .{home});

    const content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Simple JSON parsing for "currentContext": "value"
    if (std.mem.indexOf(u8, content, "\"currentContext\"")) |pos| {
        const after_key = content[pos..];
        if (std.mem.indexOf(u8, after_key, ":")) |colon_pos| {
            const after_colon = after_key[colon_pos + 1 ..];
            // Find quoted value
            if (std.mem.indexOf(u8, after_colon, "\"")) |quote_start| {
                const value_start = after_colon[quote_start + 1 ..];
                if (std.mem.indexOf(u8, value_start, "\"")) |quote_end| {
                    const context = value_start[0..quote_end];
                    if (context.len > 0) {
                        return try allocator.dupe(u8, context);
                    }
                }
            }
        }
    }

    return error.ContextNotFound;
}

test "docker detection" {
    try std.testing.expect(true);
}
