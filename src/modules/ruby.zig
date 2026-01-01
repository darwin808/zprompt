const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const RubyInfo = struct {
    version: ?[]const u8 = null,
    gemset: ?[]const u8 = null, // RVM gemset
};

/// Detect Ruby info without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?RubyInfo {
    if (!isRubyProject(cwd)) {
        return null;
    }

    return getRubyInfo(allocator, cwd) catch null;
}

/// Render Ruby info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: RubyInfo) !bool {
    var rendered = false;

    // Show Ruby version
    if (info.version) |ver| {
        try ansi.fg(writer, "via ", ansi.muted_color);
        try ansi.bold(writer, "\xee\x60\xb9 v", ansi.ruby_color); // U+E739 Ruby icon
        try ansi.fg(writer, ver, ansi.ruby_color);
        rendered = true;
    }

    // Show gemset if available
    if (info.gemset) |gemset| {
        try ansi.fg(writer, " (", ansi.muted_color);
        try ansi.fg(writer, gemset, ansi.ruby_color);
        try ansi.fg(writer, ")", ansi.muted_color);
    }

    return rendered;
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const info = detect(allocator, cwd) orelse return false;
    defer {
        if (info.version) |v| allocator.free(v);
        if (info.gemset) |g| allocator.free(g);
    }
    return try renderFromInfo(writer, info);
}

/// Quick check if this is a Ruby project (no subprocess, just file check)
pub fn exists(cwd: []const u8) bool {
    return isRubyProject(cwd);
}

fn isRubyProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    const check_files = [_][]const u8{
        "Gemfile",
        "Rakefile",
        ".ruby-version",
        ".ruby-gemset",
        "config.ru",
        "Guardfile",
    };

    for (check_files) |file| {
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ cwd, file }) catch continue;
        if (std.fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    return false;
}

fn getRubyInfo(allocator: std.mem.Allocator, cwd: []const u8) !RubyInfo {
    var info = RubyInfo{};

    // Get version: .ruby-version first, then system
    info.version = getRubyVersion(allocator, cwd) catch null;
    if (info.version == null) {
        info.version = getSystemRubyVersion(allocator) catch null;
    }

    // Get gemset from .ruby-gemset or RVM
    info.gemset = getGemset(allocator, cwd) catch null;

    return info;
}

fn getRubyVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const version_path = try std.fmt.bufPrint(&path_buf, "{s}/.ruby-version", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, version_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    // Remove "ruby-" prefix if present
    const version = if (std.mem.startsWith(u8, trimmed, "ruby-")) trimmed[5..] else trimmed;
    return try allocator.dupe(u8, version);
}

fn getGemset(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const gemset_path = try std.fmt.bufPrint(&path_buf, "{s}/.ruby-gemset", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, gemset_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    return try allocator.dupe(u8, trimmed);
}

fn getSystemRubyVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "ruby", "--version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.RubyNotFound;

    const stdout = child.stdout.?;
    var read_buffer: [256]u8 = undefined;
    const bytes_read = stdout.read(&read_buffer) catch return error.ReadFailed;

    _ = child.wait() catch return error.WaitFailed;

    if (bytes_read == 0) return error.EmptyVersion;

    // Parse "ruby X.Y.Z (...)"
    const output = std.mem.trim(u8, read_buffer[0..bytes_read], " \t\n\r");
    if (std.mem.startsWith(u8, output, "ruby ")) {
        const after_ruby = output[5..];
        // Find end of version (space or patchlevel indicator 'p')
        var end: usize = 0;
        while (end < after_ruby.len and after_ruby[end] != ' ' and after_ruby[end] != 'p') {
            end += 1;
        }
        if (end > 0) {
            return try allocator.dupe(u8, after_ruby[0..end]);
        }
    }

    return error.ParseFailed;
}

test "ruby detection" {
    try std.testing.expect(true);
}
