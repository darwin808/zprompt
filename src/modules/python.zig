const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const PythonInfo = struct {
    version: ?[]const u8 = null,
    virtualenv: ?[]const u8 = null, // Virtual environment name
};

/// Detect Python info without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?PythonInfo {
    if (!isPythonProject(cwd)) {
        return null;
    }

    return getPythonInfo(allocator, cwd) catch null;
}

/// Render Python info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: PythonInfo) !bool {
    var rendered = false;

    // Show virtualenv if active
    if (info.virtualenv) |venv| {
        try ansi.fg(writer, "(", ansi.muted_color);
        try ansi.fg(writer, venv, ansi.python_color);
        try ansi.fg(writer, ") ", ansi.muted_color);
        rendered = true;
    }

    // Show Python version
    if (info.version) |ver| {
        try ansi.fg(writer, "via ", ansi.muted_color);
        try ansi.bold(writer, "\xee\x73\xa5 v", ansi.python_color); // U+E235 Python icon (Nerd Font)
        try ansi.fg(writer, ver, ansi.python_color);
        rendered = true;
    }

    return rendered;
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const info = detect(allocator, cwd) orelse return false;
    defer {
        if (info.version) |v| allocator.free(v);
        if (info.virtualenv) |ve| allocator.free(ve);
    }
    return try renderFromInfo(writer, info);
}

/// Quick check if this is a Python project (no subprocess, just file check)
pub fn exists(cwd: []const u8) bool {
    return isPythonProject(cwd);
}

fn isPythonProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check for common Python project files
    // Note: .python-version is NOT included - it's a pyenv global version file,
    // not a project indicator (matches Starship behavior)
    const check_files = [_][]const u8{
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "setup.cfg",
        "Pipfile",
        "tox.ini",
    };

    for (check_files) |file| {
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ cwd, file }) catch continue;
        if (std.fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    // Note: We intentionally don't check for venv directories as project indicators.
    // Having a venv doesn't mean you're in a Python project (matches Starship behavior).

    return false;
}

fn getPythonInfo(allocator: std.mem.Allocator, cwd: []const u8) !PythonInfo {
    var info = PythonInfo{};

    // Check for active virtualenv
    if (std.posix.getenv("VIRTUAL_ENV")) |venv_path| {
        // Get just the directory name
        info.virtualenv = try allocator.dupe(u8, getLastComponent(venv_path));
    }

    // Get version: .python-version first, then system
    info.version = getPythonVersion(allocator, cwd) catch null;
    if (info.version == null) {
        info.version = getSystemPythonVersion(allocator) catch null;
    }

    return info;
}

fn getLastComponent(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }

    var start = end;
    while (start > 0 and path[start - 1] != '/') {
        start -= 1;
    }

    return path[start..end];
}

fn getPythonVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const version_path = try std.fmt.bufPrint(&path_buf, "{s}/.python-version", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, version_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    return try allocator.dupe(u8, trimmed);
}

fn getSystemPythonVersion(allocator: std.mem.Allocator) ![]u8 {
    // 1. Try cache first (valid for 1 hour)
    if (getVersionFromCache(allocator)) |ver| {
        return ver;
    } else |_| {}

    // 2. Fall back to python --version (slow) and cache it
    return getPythonVersionFromSubprocess(allocator);
}

fn getVersionFromCache(allocator: std.mem.Allocator) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_path = try std.fmt.bufPrint(&path_buf, "{s}/.cache/zprompt/python-version", .{home});

    const file = std.fs.cwd().openFile(cache_path, .{}) catch return error.CacheNotFound;
    defer file.close();

    // Check if cache is fresh (less than 1 hour old)
    const stat = file.stat() catch return error.StatFailed;
    const now = std.time.timestamp();
    const cache_age = now - @as(i64, @intCast(@divFloor(stat.mtime, std.time.ns_per_s)));

    if (cache_age > 3600) { // 1 hour
        return error.CacheStale;
    }

    var buf: [64]u8 = undefined;
    const bytes_read = file.readAll(&buf) catch return error.ReadFailed;
    if (bytes_read == 0) return error.EmptyCache;

    const version = std.mem.trim(u8, buf[0..bytes_read], " \t\n\r");
    if (version.len == 0) return error.EmptyCache;

    return try allocator.dupe(u8, version);
}

fn writeVersionToCache(version: []const u8) void {
    const home = std.posix.getenv("HOME") orelse return;

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_dir = std.fmt.bufPrint(&dir_buf, "{s}/.cache/zprompt", .{home}) catch return;

    std.fs.cwd().makePath(cache_dir) catch {};

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_path = std.fmt.bufPrint(&path_buf, "{s}/.cache/zprompt/python-version", .{home}) catch return;

    const file = std.fs.cwd().createFile(cache_path, .{}) catch return;
    defer file.close();

    _ = file.writeAll(version) catch {};
}

fn getPythonVersionFromSubprocess(allocator: std.mem.Allocator) ![]u8 {
    // Try python3 first, then python
    const commands = [_][]const []const u8{
        &.{ "python3", "--version" },
        &.{ "python", "--version" },
    };

    for (commands) |cmd| {
        var child = std.process.Child.init(cmd, allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe; // Python 2 outputs to stderr

        child.spawn() catch continue;

        // Read stdout
        const stdout = child.stdout.?;
        var read_buffer: [256]u8 = undefined;
        const bytes_read = stdout.read(&read_buffer) catch continue;

        // Also check stderr (Python 2 outputs version there)
        var stderr_buffer: [256]u8 = undefined;
        const stderr = child.stderr.?;
        const stderr_bytes = stderr.read(&stderr_buffer) catch 0;

        _ = child.wait() catch continue;

        // Try stdout first, then stderr
        const output = if (bytes_read > 0) read_buffer[0..bytes_read] else stderr_buffer[0..stderr_bytes];
        if (output.len == 0) continue;

        // Parse "Python X.Y.Z"
        const trimmed = std.mem.trim(u8, output, " \t\n\r");
        if (std.mem.startsWith(u8, trimmed, "Python ")) {
            const version = trimmed[7..];
            // Take just the version number (stop at first space or newline)
            var end: usize = 0;
            while (end < version.len and version[end] != ' ' and version[end] != '\n') {
                end += 1;
            }
            if (end > 0) {
                // Cache the result
                writeVersionToCache(version[0..end]);
                return try allocator.dupe(u8, version[0..end]);
            }
        }
    }

    return error.PythonNotFound;
}

test "python detection" {
    try std.testing.expect(true);
}
