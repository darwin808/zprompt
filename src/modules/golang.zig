const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const GoInfo = struct {
    version: ?[]const u8 = null,
    version_source: VersionSource = .none,
};

pub const VersionSource = enum {
    none,
    go_version_file,
    go_mod,
    system,
};

/// Detect Go project without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?GoInfo {
    if (!isGoProject(cwd)) {
        return null;
    }

    var info = GoInfo{};

    // Priority: .go-version > go.mod > system
    info.version = getVersionFromFile(allocator, cwd) catch null;
    if (info.version != null) {
        info.version_source = .go_version_file;
    } else {
        info.version = getVersionFromGoMod(allocator, cwd) catch null;
        if (info.version != null) {
            info.version_source = .go_mod;
        } else {
            info.version = getSystemGoVersion(allocator) catch null;
            if (info.version != null) {
                info.version_source = .system;
            }
        }
    }

    return info;
}

/// Render Go info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: GoInfo) !bool {
    if (info.version) |ver| {
        try ansi.fg(writer, "via ", ansi.muted_color);
        // Go icon U+E724
        try ansi.bold(writer, "\xee\x9c\xa4 v", ansi.go_color);
        try ansi.fg(writer, ver, ansi.go_color);
        return true;
    }
    return false;
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const info = detect(allocator, cwd) orelse return false;
    defer {
        if (info.version) |v| allocator.free(v);
    }
    return try renderFromInfo(writer, info);
}

fn isGoProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check for go.mod
    const gomod_path = std.fmt.bufPrint(&path_buf, "{s}/go.mod", .{cwd}) catch return false;
    if (std.fs.cwd().access(gomod_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for go.sum
    const gosum_path = std.fmt.bufPrint(&path_buf, "{s}/go.sum", .{cwd}) catch return false;
    if (std.fs.cwd().access(gosum_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for .go-version
    const gv_path = std.fmt.bufPrint(&path_buf, "{s}/.go-version", .{cwd}) catch return false;
    if (std.fs.cwd().access(gv_path, .{})) |_| {
        return true;
    } else |_| {}

    return false;
}

fn getVersionFromFile(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const gv_path = try std.fmt.bufPrint(&path_buf, "{s}/.go-version", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, gv_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    return try allocator.dupe(u8, trimmed);
}

fn getVersionFromGoMod(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const gomod_path = try std.fmt.bufPrint(&path_buf, "{s}/go.mod", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, gomod_path, 64 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Look for "go X.Y" or "go X.Y.Z" directive
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "go ")) {
            const version = std.mem.trim(u8, trimmed[3..], " \t");
            if (version.len > 0) {
                return try allocator.dupe(u8, version);
            }
        }
    }

    return error.VersionNotFound;
}

fn getSystemGoVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "go", "version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.GoNotFound;

    const stdout = child.stdout.?;
    var read_buffer: [256]u8 = undefined;
    const bytes_read = stdout.read(&read_buffer) catch return error.ReadFailed;

    _ = child.wait() catch return error.WaitFailed;

    if (bytes_read == 0) return error.EmptyVersion;

    // Parse "go version go1.21.5 darwin/arm64" -> extract "1.21.5"
    const output = std.mem.trim(u8, read_buffer[0..bytes_read], " \t\n\r");

    // Find "go1.X.Y" pattern
    if (std.mem.indexOf(u8, output, "go1.")) |idx| {
        const version_start = idx + 2; // Skip "go", keep "1."
        var end = version_start;
        while (end < output.len and (std.ascii.isDigit(output[end]) or output[end] == '.')) {
            end += 1;
        }
        if (end > version_start) {
            return try allocator.dupe(u8, output[version_start..end]);
        }
    }

    return error.VersionNotFound;
}

test "go project detection" {
    try std.testing.expect(true);
}
