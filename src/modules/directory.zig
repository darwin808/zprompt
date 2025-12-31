const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !void {
    const display_path = try getDisplayPath(allocator, cwd);
    defer allocator.free(display_path);

    try ansi.bold(writer, display_path, ansi.dir_color);
}

fn getDisplayPath(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    // Get home directory
    const home = std.posix.getenv("HOME") orelse "";

    // Check if we're in a git repo - if so, show path relative to repo root
    if (findGitRepoRoot(cwd)) |repo_root| {
        if (std.mem.eql(u8, cwd, repo_root)) {
            // At repo root - just show folder name
            return try getLastComponent(allocator, cwd);
        } else if (std.mem.startsWith(u8, cwd, repo_root)) {
            // Inside repo - show repo_name/sub/path
            const repo_name = getLastComponentSlice(repo_root);
            const relative = cwd[repo_root.len..];
            var result: std.ArrayList(u8) = .{};
            errdefer result.deinit(allocator);
            try result.appendSlice(allocator, repo_name);
            try result.appendSlice(allocator, relative);
            return result.toOwnedSlice(allocator);
        }
    }

    // Replace home with ~
    if (home.len > 0 and std.mem.startsWith(u8, cwd, home)) {
        const relative = cwd[home.len..];
        if (relative.len == 0) {
            return try allocator.dupe(u8, "~");
        }
        // Show ~/last_folder or truncated path
        return try truncatePath(allocator, cwd, home, 3);
    }

    // Truncate path if too long (keep last 3 components)
    return try truncatePathSimple(allocator, cwd, 3);
}

fn findGitRepoRoot(start_path: []const u8) ?[]const u8 {
    var path = start_path;
    while (true) {
        // Check for .git directory
        var git_buf: [std.fs.max_path_bytes]u8 = undefined;
        const git_path = std.fmt.bufPrint(&git_buf, "{s}/.git", .{path}) catch return null;

        if (std.fs.cwd().access(git_path, .{})) |_| {
            return path;
        } else |_| {}

        // Go up one directory
        if (std.fs.path.dirname(path)) |parent| {
            path = parent;
        } else {
            return null;
        }

        if (path.len == 0 or std.mem.eql(u8, path, "/")) {
            return null;
        }
    }
}

fn getLastComponent(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try allocator.dupe(u8, getLastComponentSlice(path));
}

fn getLastComponentSlice(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    var end = path.len;
    // Skip trailing slashes
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }

    // Find the last slash
    var start = end;
    while (start > 0 and path[start - 1] != '/') {
        start -= 1;
    }

    return path[start..end];
}

fn truncatePath(allocator: std.mem.Allocator, path: []const u8, home: []const u8, keep_components: usize) ![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, "");

    // Get path relative to home
    const relative = if (home.len > 0 and std.mem.startsWith(u8, path, home))
        path[home.len..]
    else
        path;

    var components: std.ArrayList([]const u8) = .{};
    defer components.deinit(allocator);

    var iter = std.mem.splitScalar(u8, relative, '/');
    while (iter.next()) |comp| {
        if (comp.len > 0) {
            try components.append(allocator, comp);
        }
    }

    const items = components.items;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    if (items.len <= keep_components) {
        // Show full path with ~
        try result.append(allocator, '~');
        try result.appendSlice(allocator, relative);
        return result.toOwnedSlice(allocator);
    }

    // Take last N components with ~
    const start_idx = items.len - keep_components;
    try result.appendSlice(allocator, "~/…/");

    for (items[start_idx..], 0..) |comp, i| {
        if (i > 0) try result.append(allocator, '/');
        try result.appendSlice(allocator, comp);
    }

    return result.toOwnedSlice(allocator);
}

fn truncatePathSimple(allocator: std.mem.Allocator, path: []const u8, keep_components: usize) ![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, "");

    var components: std.ArrayList([]const u8) = .{};
    defer components.deinit(allocator);

    var iter = std.mem.splitScalar(u8, path, '/');
    while (iter.next()) |comp| {
        if (comp.len > 0) {
            try components.append(allocator, comp);
        }
    }

    const items = components.items;
    if (items.len <= keep_components) {
        return try allocator.dupe(u8, path);
    }

    // Take last N components
    const start_idx = items.len - keep_components;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "…/");

    for (items[start_idx..], 0..) |comp, i| {
        if (i > 0) try result.append(allocator, '/');
        try result.appendSlice(allocator, comp);
    }

    return result.toOwnedSlice(allocator);
}

test "path truncation" {
    const allocator = std.testing.allocator;

    const result = try truncatePathSimple(allocator, "/a/b/c/d/e", 3);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("…/c/d/e", result);
}
