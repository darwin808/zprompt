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

    // Replace home with ~
    if (home.len > 0 and std.mem.startsWith(u8, cwd, home)) {
        const relative = cwd[home.len..];
        if (relative.len == 0) {
            return try allocator.dupe(u8, "~");
        }
        var result = try allocator.alloc(u8, 1 + relative.len);
        result[0] = '~';
        @memcpy(result[1..], relative);
        return result;
    }

    // Truncate path if too long (keep last 3 components)
    return try truncatePath(allocator, cwd, 3);
}

fn truncatePath(allocator: std.mem.Allocator, path: []const u8, keep_components: usize) ![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, "");

    var components = std.ArrayList([]const u8).init(allocator);
    defer components.deinit();

    var iter = std.mem.splitScalar(u8, path, '/');
    while (iter.next()) |comp| {
        if (comp.len > 0) {
            try components.append(comp);
        }
    }

    const items = components.items;
    if (items.len <= keep_components) {
        return try allocator.dupe(u8, path);
    }

    // Take last N components
    const start = items.len - keep_components;
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Add truncation indicator
    try result.appendSlice("…/");

    for (items[start..], 0..) |comp, i| {
        if (i > 0) try result.append('/');
        try result.appendSlice(comp);
    }

    return result.toOwnedSlice();
}

test "home replacement" {
    const allocator = std.testing.allocator;

    // Would need to mock HOME for proper testing
    const result = try truncatePath(allocator, "/a/b/c/d/e", 3);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("…/c/d/e", result);
}
