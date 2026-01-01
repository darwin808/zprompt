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
    info.version = getRustVersion(allocator, cwd) catch null;
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

fn getRustVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    // 1. Try rust-toolchain.toml first (no subprocess!)
    if (getVersionFromToolchainToml(allocator, cwd)) |ver| {
        return ver;
    } else |_| {}

    // 2. Try rust-toolchain file
    if (getVersionFromToolchainFile(allocator, cwd)) |ver| {
        return ver;
    } else |_| {}

    // 3. Try cache (valid for 1 hour)
    if (getVersionFromCache(allocator)) |ver| {
        return ver;
    } else |_| {}

    // 4. Fall back to rustc --version (slow) and cache it
    return getRustVersionFromSubprocess(allocator);
}

fn getVersionFromToolchainToml(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const toolchain_path = try std.fmt.bufPrint(&path_buf, "{s}/rust-toolchain.toml", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, toolchain_path, 64 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Parse: [toolchain]
    //        channel = "1.91.1" or "stable" or "nightly-2024-01-01"
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "channel")) {
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
                // Extract version if it's like "1.91.1" or "1.91"
                if (value.len > 0 and value[0] >= '0' and value[0] <= '9') {
                    return try allocator.dupe(u8, value);
                }
                // For "stable", "beta", "nightly" - return as-is
                if (std.mem.eql(u8, value, "stable") or std.mem.eql(u8, value, "beta") or std.mem.startsWith(u8, value, "nightly")) {
                    return try allocator.dupe(u8, value);
                }
            }
        }
    }
    return error.VersionNotFound;
}

fn getVersionFromToolchainFile(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const toolchain_path = try std.fmt.bufPrint(&path_buf, "{s}/rust-toolchain", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, toolchain_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    return try allocator.dupe(u8, trimmed);
}

fn getVersionFromCache(allocator: std.mem.Allocator) ![]u8 {
    // Cache location: ~/.cache/zprompt/rustc-version
    const home = std.posix.getenv("HOME") orelse return error.NoHome;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_path = try std.fmt.bufPrint(&path_buf, "{s}/.cache/zprompt/rustc-version", .{home});

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

fn getRustVersionFromSubprocess(allocator: std.mem.Allocator) ![]u8 {
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

    var version: []const u8 = output;
    // Skip "rustc " prefix
    if (std.mem.startsWith(u8, output, "rustc ")) {
        const after_rustc = output[6..];
        // Find the space before the hash
        if (std.mem.indexOf(u8, after_rustc, " ")) |space_idx| {
            version = after_rustc[0..space_idx];
        } else {
            version = after_rustc;
        }
    }

    // Cache the result
    writeVersionToCache(version);

    return try allocator.dupe(u8, version);
}

fn writeVersionToCache(version: []const u8) void {
    const home = std.posix.getenv("HOME") orelse return;

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_dir = std.fmt.bufPrint(&dir_buf, "{s}/.cache/zprompt", .{home}) catch return;

    // Create cache directory if needed
    std.fs.cwd().makePath(cache_dir) catch {};

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cache_path = std.fmt.bufPrint(&path_buf, "{s}/.cache/zprompt/rustc-version", .{home}) catch return;

    const file = std.fs.cwd().createFile(cache_path, .{}) catch return;
    defer file.close();

    _ = file.writeAll(version) catch {};
}

test "rust project detection" {
    try std.testing.expect(true);
}
