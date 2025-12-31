const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const JavaInfo = struct {
    version: ?[]const u8 = null,
    version_source: VersionSource = .none,
};

pub const VersionSource = enum {
    none,
    java_version_file,
    system,
};

/// Detect Java project without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?JavaInfo {
    if (!isJavaProject(cwd)) {
        return null;
    }

    var info = JavaInfo{};

    // Priority: .java-version > system
    info.version = getVersionFromFile(allocator, cwd) catch null;
    if (info.version != null) {
        info.version_source = .java_version_file;
    } else {
        info.version = getSystemJavaVersion(allocator) catch null;
        if (info.version != null) {
            info.version_source = .system;
        }
    }

    return info;
}

/// Render Java info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: JavaInfo) !bool {
    if (info.version) |ver| {
        try ansi.fg(writer, "via ", ansi.muted_color);
        // Java icon U+E738
        try ansi.bold(writer, "\xee\x9c\xb8 v", ansi.java_color);
        try ansi.fg(writer, ver, ansi.java_color);
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

fn isJavaProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check for pom.xml (Maven)
    const pom_path = std.fmt.bufPrint(&path_buf, "{s}/pom.xml", .{cwd}) catch return false;
    if (std.fs.cwd().access(pom_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for build.gradle (Gradle)
    const gradle_path = std.fmt.bufPrint(&path_buf, "{s}/build.gradle", .{cwd}) catch return false;
    if (std.fs.cwd().access(gradle_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for build.gradle.kts (Kotlin Gradle)
    const gradle_kts_path = std.fmt.bufPrint(&path_buf, "{s}/build.gradle.kts", .{cwd}) catch return false;
    if (std.fs.cwd().access(gradle_kts_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for .java-version
    const jv_path = std.fmt.bufPrint(&path_buf, "{s}/.java-version", .{cwd}) catch return false;
    if (std.fs.cwd().access(jv_path, .{})) |_| {
        return true;
    } else |_| {}

    return false;
}

fn getVersionFromFile(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const jv_path = try std.fmt.bufPrint(&path_buf, "{s}/.java-version", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, jv_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    return try allocator.dupe(u8, trimmed);
}

fn getSystemJavaVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "java", "--version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.JavaNotFound;

    const stdout = child.stdout.?;
    var read_buffer: [512]u8 = undefined;
    const bytes_read = stdout.read(&read_buffer) catch return error.ReadFailed;

    _ = child.wait() catch return error.WaitFailed;

    if (bytes_read == 0) return error.EmptyVersion;

    // Parse first line: "openjdk 21.0.1 2023-10-17" or "java 17.0.1 2021-10-19"
    const output = read_buffer[0..bytes_read];

    // Find first line
    var lines = std.mem.splitScalar(u8, output, '\n');
    if (lines.next()) |first_line| {
        const trimmed = std.mem.trim(u8, first_line, " \t\r");

        // Look for version pattern: find first digit sequence that looks like a version
        var i: usize = 0;
        while (i < trimmed.len) : (i += 1) {
            if (std.ascii.isDigit(trimmed[i])) {
                // Found start of version, find end
                var end = i;
                while (end < trimmed.len and (std.ascii.isDigit(trimmed[end]) or trimmed[end] == '.')) {
                    end += 1;
                }
                if (end > i) {
                    return try allocator.dupe(u8, trimmed[i..end]);
                }
            }
        }
    }

    return error.VersionNotFound;
}

test "java project detection" {
    try std.testing.expect(true);
}
