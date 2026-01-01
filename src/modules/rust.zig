const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const RustInfo = struct {
    version: ?[]const u8 = null,
    package_version: ?[]const u8 = null,
};

/// Detect Rust project without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?RustInfo {
    if (!isRustProject(cwd)) {
        return null;
    }

    var info = RustInfo{};
    info.package_version = getPackageVersion(allocator, cwd) catch null;
    info.version = getRustVersion(allocator) catch null;
    return info;
}

/// Render Rust info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: RustInfo) !bool {
    var rendered = false;

    // Show package version (📦 v0.4.0)
    if (info.package_version) |pkg_ver| {
        try ansi.fg(writer, "is ", ansi.muted_color);
        try ansi.bold(writer, "📦 v", ansi.package_color);
        try ansi.fg(writer, pkg_ver, ansi.package_color);
        rendered = true;
    }

    // Show Rust version (🦀 v1.91.1)
    if (info.version) |ver| {
        if (rendered) try writer.writeAll(" ");
        try ansi.fg(writer, "via ", ansi.muted_color);
        try ansi.bold(writer, "🦀 v", ansi.rust_color);
        try ansi.fg(writer, ver, ansi.rust_color);
        rendered = true;
    }

    return rendered;
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const info = detect(allocator, cwd) orelse return false;
    defer {
        if (info.version) |v| allocator.free(v);
        if (info.package_version) |pv| allocator.free(pv);
    }
    return try renderFromInfo(writer, info);
}

/// Quick check if this is a Rust project (no subprocess, just file check)
pub fn exists(cwd: []const u8) bool {
    return isRustProject(cwd);
}

fn isRustProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check for Cargo.toml
    const cargo_path = std.fmt.bufPrint(&path_buf, "{s}/Cargo.toml", .{cwd}) catch return false;
    if (std.fs.cwd().access(cargo_path, .{})) |_| {
        return true;
    } else |_| {}

    return false;
}

fn getPackageVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cargo_path = try std.fmt.bufPrint(&path_buf, "{s}/Cargo.toml", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, cargo_path, 1024 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Simple TOML parsing for version = "x.y.z" in [package] section
    // Look for version after [package]
    var in_package = false;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Check for [package] section
        if (std.mem.eql(u8, trimmed, "[package]")) {
            in_package = true;
            continue;
        }

        // Check for other sections
        if (trimmed.len > 0 and trimmed[0] == '[') {
            in_package = false;
            continue;
        }

        // Look for version in package section
        if (in_package) {
            if (std.mem.startsWith(u8, trimmed, "version")) {
                // Find = sign
                if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                    var value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");
                    // Remove quotes
                    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                        value = value[1 .. value.len - 1];
                    }
                    if (value.len > 0) {
                        return try allocator.dupe(u8, value);
                    }
                }
            }
        }
    }

    return error.VersionNotFound;
}

fn getRustVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "rustc", "--version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.RustcNotFound;

    const stdout = child.stdout.?;
    var read_buffer: [256]u8 = undefined;
    const bytes_read = stdout.read(&read_buffer) catch return error.ReadFailed;

    _ = child.wait() catch return error.WaitFailed;

    if (bytes_read == 0) return error.EmptyVersion;

    // Parse "rustc X.Y.Z (hash date)" -> extract "X.Y.Z"
    const output = std.mem.trim(u8, read_buffer[0..bytes_read], " \t\n\r");

    // Skip "rustc " prefix
    if (std.mem.startsWith(u8, output, "rustc ")) {
        const after_rustc = output[6..];
        // Find the space before the hash
        if (std.mem.indexOf(u8, after_rustc, " ")) |space_idx| {
            return try allocator.dupe(u8, after_rustc[0..space_idx]);
        }
        return try allocator.dupe(u8, after_rustc);
    }

    return try allocator.dupe(u8, output);
}

test "rust project detection" {
    try std.testing.expect(true);
}
