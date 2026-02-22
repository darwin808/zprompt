const std = @import("std");
const object = @import("object.zig");

/// Build a flat map of path -> SHA for all entries in the HEAD tree.
/// Returns a StringHashMap mapping file paths to their 20-byte SHAs.
pub fn getHeadTree(allocator: std.mem.Allocator, git_dir: []const u8) !std.StringHashMap([20]u8) {
    // 1. Resolve HEAD to a commit SHA
    const commit_sha = try resolveHead(allocator, git_dir);

    // 2. Read commit object, extract tree SHA
    const tree_sha = try getTreeFromCommit(allocator, git_dir, &commit_sha);

    // 3. Recursively walk tree to build flat path map
    var map = std.StringHashMap([20]u8).init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        map.deinit();
    }

    const tree_hex = object.shaToHex(tree_sha);
    try walkTree(allocator, git_dir, &tree_hex, "", &map);

    return map;
}

/// Count staged files by comparing index entries against HEAD tree.
pub fn countStaged(allocator: std.mem.Allocator, git_dir: []const u8, index_entries: anytype) !u32 {
    const head_tree = getHeadTree(allocator, git_dir) catch |err| {
        if (err == error.EmptyRepo) {
            // Empty repo: all index entries are staged
            var count: u32 = 0;
            for (index_entries) |entry| {
                if (!entry.isConflicted()) count += 1;
            }
            return count;
        }
        return err;
    };
    defer {
        var it = head_tree.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        // Can't call deinit on const, but we're using arena anyway
        var mutable = head_tree;
        mutable.deinit();
    }

    var count: u32 = 0;

    // Check each index entry against HEAD tree
    for (index_entries) |entry| {
        if (entry.isConflicted()) continue;

        if (head_tree.get(entry.path)) |tree_sha| {
            // File exists in both — compare SHAs
            if (!std.mem.eql(u8, &entry.sha1, &tree_sha)) {
                count += 1; // Modified (staged)
            }
        } else {
            // In index but not in HEAD tree = new file (staged)
            count += 1;
        }
    }

    // Check for deletions: files in HEAD tree but not in index
    // Build a set of index paths for quick lookup
    var index_paths = std.StringHashMap(void).init(allocator);
    defer index_paths.deinit();
    for (index_entries) |entry| {
        if (!entry.isConflicted()) {
            try index_paths.put(entry.path, {});
        }
    }

    var tree_iter = head_tree.iterator();
    while (tree_iter.next()) |entry| {
        if (!index_paths.contains(entry.key_ptr.*)) {
            count += 1; // Deleted (staged)
        }
    }

    return count;
}

fn resolveHead(allocator: std.mem.Allocator, git_dir: []const u8) ![40]u8 {
    var head_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const head_path = try std.fmt.bufPrint(&head_path_buf, "{s}/HEAD", .{git_dir});

    const head_content = std.fs.cwd().readFileAlloc(allocator, head_path, 1024) catch {
        return error.CannotReadHead;
    };
    defer allocator.free(head_content);

    const trimmed = std.mem.trim(u8, head_content, " \t\n\r");

    if (std.mem.startsWith(u8, trimmed, "ref: ")) {
        // Symbolic ref — resolve it
        const ref = trimmed[5..];
        return resolveRef(allocator, git_dir, ref);
    }

    // Detached HEAD — direct SHA
    if (trimmed.len >= 40) {
        var sha: [40]u8 = undefined;
        @memcpy(&sha, trimmed[0..40]);
        return sha;
    }

    return error.InvalidHead;
}

fn resolveRef(allocator: std.mem.Allocator, git_dir: []const u8, ref: []const u8) ![40]u8 {
    // Try loose ref first
    var ref_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const ref_path = try std.fmt.bufPrint(&ref_path_buf, "{s}/{s}", .{ git_dir, ref });

    if (std.fs.cwd().readFileAlloc(allocator, ref_path, 1024)) |content| {
        defer allocator.free(content);
        const trimmed = std.mem.trim(u8, content, " \t\n\r");
        if (trimmed.len >= 40) {
            var sha: [40]u8 = undefined;
            @memcpy(&sha, trimmed[0..40]);
            return sha;
        }
    } else |_| {}

    // Try packed-refs
    var packed_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const packed_path = try std.fmt.bufPrint(&packed_path_buf, "{s}/packed-refs", .{git_dir});

    if (std.fs.cwd().readFileAlloc(allocator, packed_path, 10 * 1024 * 1024)) |content| {
        defer allocator.free(content);
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] == '#' or line[0] == '^') continue;
            // Format: "<sha> <ref>"
            if (line.len >= 41 and line[40] == ' ') {
                const line_ref = line[41..];
                if (std.mem.eql(u8, line_ref, ref)) {
                    var sha: [40]u8 = undefined;
                    @memcpy(&sha, line[0..40]);
                    return sha;
                }
            }
        }
    } else |_| {}

    return error.EmptyRepo;
}

fn getTreeFromCommit(allocator: std.mem.Allocator, git_dir: []const u8, commit_hex: []const u8) ![20]u8 {
    const raw = try object.readObject(allocator, git_dir, commit_hex);
    defer allocator.free(raw);

    const obj = try object.parseObject(raw);
    if (obj.obj_type != .commit) return error.NotACommit;

    // Parse commit object — first line should be "tree <sha>"
    var lines = std.mem.splitScalar(u8, obj.data, '\n');
    if (lines.next()) |first_line| {
        if (std.mem.startsWith(u8, first_line, "tree ") and first_line.len >= 45) {
            var sha: [20]u8 = undefined;
            object.hexToSha(first_line[5..45], &sha) catch return error.InvalidCommit;
            return sha;
        }
    }

    return error.InvalidCommit;
}

fn walkTree(
    allocator: std.mem.Allocator,
    git_dir: []const u8,
    tree_hex: []const u8,
    prefix: []const u8,
    map: *std.StringHashMap([20]u8),
) !void {
    const raw = try object.readObject(allocator, git_dir, tree_hex);
    defer allocator.free(raw);

    const obj = try object.parseObject(raw);
    if (obj.obj_type != .tree) return error.NotATree;

    // Tree format: repeated entries of "<mode> <name>\0<20-byte-sha>"
    var pos: usize = 0;
    const data = obj.data;

    while (pos < data.len) {
        // Find space (end of mode)
        const space_pos = std.mem.indexOfScalar(u8, data[pos..], ' ') orelse break;
        const mode = data[pos .. pos + space_pos];
        pos += space_pos + 1;

        // Find NUL (end of name)
        const nul_pos = std.mem.indexOfScalar(u8, data[pos..], 0) orelse break;
        const name = data[pos .. pos + nul_pos];
        pos += nul_pos + 1;

        // Read 20-byte SHA
        if (pos + 20 > data.len) break;
        const sha = data[pos..][0..20].*;
        pos += 20;

        // Build full path
        const full_path = if (prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, name })
        else
            try allocator.dupe(u8, name);

        // Check if this is a tree (directory) — mode starts with "40" (40000)
        if (std.mem.startsWith(u8, mode, "40")) {
            defer allocator.free(full_path);
            const sub_hex = object.shaToHex(sha);
            try walkTree(allocator, git_dir, &sub_hex, full_path, map);
        } else {
            try map.put(full_path, sha);
        }
    }
}

test "tree module compiles" {
    try std.testing.expect(true);
}
