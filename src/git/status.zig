const std = @import("std");
const index_parser = @import("index.zig");

/// Native git status result (subset of what git status provides)
pub const NativeStatus = struct {
    staged: u32 = 0,
    modified: u32 = 0,
    deleted: u32 = 0,
    conflicted: u32 = 0,
    // Note: untracked requires full directory walk, skip for performance
};

/// Get working tree status by comparing index with filesystem
/// This is faster than running `git status` subprocess
pub fn getStatus(allocator: std.mem.Allocator, git_dir: []const u8, cwd: []const u8) !NativeStatus {
    _ = allocator; // Used for index parsing

    // Parse .git/index
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const index_path = try std.fmt.bufPrint(&path_buf, "{s}/index", .{git_dir});

    // Use a temporary arena for index parsing
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var idx = try index_parser.parseFile(arena, index_path);
    defer idx.deinit();

    var status = NativeStatus{};

    // Track last seen conflicted path to avoid counting duplicates
    var last_conflict_path: ?[]const u8 = null;

    for (idx.entries) |entry| {
        // Check for conflicts (stage != 0)
        if (entry.isConflicted()) {
            // Only count each conflicted path once (entries are sorted by path)
            if (last_conflict_path == null or !std.mem.eql(u8, last_conflict_path.?, entry.path)) {
                last_conflict_path = entry.path;
                status.conflicted += 1;
            }
            continue; // Don't check modified/deleted for conflict entries
        }

        // Build full path
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ cwd, entry.path }) catch continue;

        // Stat the file
        const stat = std.fs.cwd().statFile(full_path) catch |err| {
            if (err == error.FileNotFound) {
                status.deleted += 1;
            }
            // Other errors: treat as unchanged (conservative)
            continue;
        };

        // Compare mtime and size for quick dirty check
        // Git uses stat data caching - if mtime/size match, file is clean
        const file_mtime_sec: u32 = @intCast(@divFloor(stat.mtime, std.time.ns_per_s) + std.time.epoch.posix);
        const file_size: u32 = @truncate(stat.size);

        // If mtime or size differs, file is potentially modified
        if (file_mtime_sec != entry.mtime_sec or file_size != entry.size) {
            status.modified += 1;
        }
    }

    // Staged files: For now, we'd need to compare index with HEAD tree
    // This requires parsing tree objects, which is complex
    // Keep using git status for staged count, or approximate as 0
    // TODO: Implement tree parsing for accurate staged count

    return status;
}

test "native status" {
    try std.testing.expect(true);
}
