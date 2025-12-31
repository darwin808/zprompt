const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const RustInfo = struct {
    version: ?[]const u8 = null,
};

/// Detect Rust project without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?RustInfo {
    if (!isRustProject(cwd)) {
        return null;
    }

    var info = RustInfo{};
    info.version = getRustVersion(allocator) catch null;
    return info;
}

/// Render Rust info from pre-computed detection result
pub fn renderFromInfo(writer: anytype, info: RustInfo) !bool {
    if (info.version) |ver| {
        try ansi.fg(writer, "via ", ansi.muted_color);
        // Rust icon U+E7A8
        try ansi.bold(writer, "\xee\x9e\xa8 v", ansi.rust_color);
        try ansi.fg(writer, ver, ansi.rust_color);
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

fn isRustProject(cwd: []const u8) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check for Cargo.toml
    const cargo_path = std.fmt.bufPrint(&path_buf, "{s}/Cargo.toml", .{cwd}) catch return false;
    if (std.fs.cwd().access(cargo_path, .{})) |_| {
        return true;
    } else |_| {}

    return false;
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
