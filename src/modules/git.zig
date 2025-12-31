const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const GitStatus = struct {
    branch: ?[]const u8 = null,
    ahead: u32 = 0,
    behind: u32 = 0,
    staged: u32 = 0,
    modified: u32 = 0,
    untracked: u32 = 0,
    deleted: u32 = 0,
    renamed: u32 = 0,
    conflicted: u32 = 0,
    stash_count: u32 = 0,
    repo_state: ?[]const u8 = null,
};

/// Detect git status without rendering (for parallel execution)
pub fn detect(allocator: std.mem.Allocator, cwd: []const u8) ?GitStatus {
    // Find git directory - return null if not in a repo
    const git_dir = findGitDir(allocator, cwd) catch return null;
    defer allocator.free(git_dir);

    // Get status
    return getStatus(allocator, cwd) catch null;
}

/// Render git status from pre-computed detection result
pub fn renderFromStatus(writer: anytype, status: GitStatus) !void {
    // Render branch with Powerline icon U+E0A0
    try ansi.fg(writer, "on ", ansi.muted_color);
    try ansi.bold(writer, "\xee\x82\xa0 ", ansi.git_branch_color);

    if (status.branch) |branch| {
        try ansi.bold(writer, branch, ansi.git_branch_color);
    } else {
        try ansi.bold(writer, "HEAD", ansi.git_branch_color);
    }

    // Repo state (rebasing, merging, etc.)
    if (status.repo_state) |state| {
        try ansi.fg(writer, " (", .bright_black);
        try ansi.fg(writer, state, ansi.git_status_color);
        try ansi.fg(writer, ")", .bright_black);
    }

    // Status indicators (Starship style - symbols only, no counts)
    var has_status = false;
    var status_buf: [64]u8 = undefined;
    var status_len: usize = 0;

    // Helper to append symbol to status buffer
    const appendSymbol = struct {
        fn call(buf: []u8, len: *usize, symbol: []const u8) void {
            if (len.* + symbol.len <= buf.len) {
                @memcpy(buf[len.*..][0..symbol.len], symbol);
                len.* += symbol.len;
            }
        }
    }.call;

    if (status.ahead > 0) {
        appendSymbol(&status_buf, &status_len, "⇡");
        has_status = true;
    }

    if (status.behind > 0) {
        appendSymbol(&status_buf, &status_len, "⇣");
        has_status = true;
    }

    if (status.staged > 0) {
        appendSymbol(&status_buf, &status_len, "+");
        has_status = true;
    }

    if (status.modified > 0) {
        appendSymbol(&status_buf, &status_len, "!");
        has_status = true;
    }

    if (status.untracked > 0) {
        appendSymbol(&status_buf, &status_len, "?");
        has_status = true;
    }

    if (status.deleted > 0) {
        appendSymbol(&status_buf, &status_len, "✘");
        has_status = true;
    }

    if (status.conflicted > 0) {
        appendSymbol(&status_buf, &status_len, "=");
        has_status = true;
    }

    if (status.stash_count > 0) {
        appendSymbol(&status_buf, &status_len, "$");
        has_status = true;
    }

    if (has_status) {
        try writer.writeAll(" [");
        try ansi.fg(writer, status_buf[0..status_len], ansi.git_status_color);
        try writer.writeAll("]");
    }
}

/// Convenience wrapper for non-parallel use
pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    const status = detect(allocator, cwd) orelse return false;
    defer {
        if (status.branch) |b| allocator.free(b);
        if (status.repo_state) |s| allocator.free(s);
    }
    try renderFromStatus(writer, status);
    return true;
}

fn findGitDir(allocator: std.mem.Allocator, start_path: []const u8) ![]u8 {
    var path = try allocator.dupe(u8, start_path);
    defer allocator.free(path);

    while (true) {
        // Check for .git directory
        const git_path = try std.fs.path.join(allocator, &.{ path, ".git" });
        defer allocator.free(git_path);

        if (std.fs.cwd().access(git_path, .{})) |_| {
            return try allocator.dupe(u8, git_path);
        } else |_| {}

        // Go up one directory
        if (std.fs.path.dirname(path)) |parent| {
            const new_path = try allocator.dupe(u8, parent);
            allocator.free(path);
            path = new_path;
        } else {
            return error.NotAGitRepository;
        }

        // Stop at root
        if (path.len == 0 or std.mem.eql(u8, path, "/")) {
            return error.NotAGitRepository;
        }
    }
}

fn getStatus(allocator: std.mem.Allocator, cwd: []const u8) !GitStatus {
    var status = GitStatus{};

    // Get branch name from .git/HEAD
    status.branch = getBranch(allocator, cwd) catch null;

    // Get status from git status --porcelain=v2 --branch
    const result = runGitCommand(allocator, cwd, &.{ "status", "--porcelain=v2", "--branch" }) catch {
        return status;
    };
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        if (std.mem.startsWith(u8, line, "# branch.ab ")) {
            // Parse ahead/behind: "# branch.ab +1 -2"
            var parts = std.mem.splitScalar(u8, line[13..], ' ');
            if (parts.next()) |ahead_str| {
                if (ahead_str.len > 1 and ahead_str[0] == '+') {
                    status.ahead = std.fmt.parseInt(u32, ahead_str[1..], 10) catch 0;
                }
            }
            if (parts.next()) |behind_str| {
                if (behind_str.len > 1 and behind_str[0] == '-') {
                    status.behind = std.fmt.parseInt(u32, behind_str[1..], 10) catch 0;
                }
            }
        } else if (line[0] == '1' or line[0] == '2') {
            // Changed entry
            if (line.len > 2) {
                const xy = line[2..4];
                // First char is staged status
                if (xy[0] != '.') {
                    status.staged += 1;
                }
                // Second char is worktree status
                switch (xy[1]) {
                    'M' => status.modified += 1,
                    'D' => status.deleted += 1,
                    else => {},
                }
            }
        } else if (line[0] == '?') {
            status.untracked += 1;
        } else if (line[0] == 'u') {
            status.conflicted += 1;
        }
    }

    // Get stash count
    status.stash_count = getStashCount(allocator, cwd) catch 0;

    // Get repo state
    status.repo_state = getRepoState(allocator, cwd) catch null;

    return status;
}

fn getBranch(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    // Find .git directory
    const git_dir = try findGitDir(allocator, cwd);
    defer allocator.free(git_dir);

    // Read HEAD
    const head_path = try std.fs.path.join(allocator, &.{ git_dir, "HEAD" });
    defer allocator.free(head_path);

    const head_content = std.fs.cwd().readFileAlloc(allocator, head_path, 1024) catch {
        return error.CannotReadHead;
    };
    defer allocator.free(head_content);

    // Parse ref: refs/heads/branch-name
    const trimmed = std.mem.trim(u8, head_content, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "ref: refs/heads/")) {
        return try allocator.dupe(u8, trimmed[16..]);
    }

    // Detached HEAD - return short SHA
    if (trimmed.len >= 7) {
        return try allocator.dupe(u8, trimmed[0..7]);
    }

    return error.InvalidHead;
}

fn getStashCount(allocator: std.mem.Allocator, cwd: []const u8) !u32 {
    const result = runGitCommand(allocator, cwd, &.{ "stash", "list" }) catch {
        return 0;
    };
    defer allocator.free(result);

    var count: u32 = 0;
    var lines = std.mem.splitScalar(u8, result, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) count += 1;
    }
    return count;
}

fn getRepoState(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const git_dir = try findGitDir(allocator, cwd);
    defer allocator.free(git_dir);

    // Check for various state files
    const states = .{
        .{ "rebase-merge", "REBASING" },
        .{ "rebase-apply", "REBASING" },
        .{ "MERGE_HEAD", "MERGING" },
        .{ "CHERRY_PICK_HEAD", "CHERRY-PICKING" },
        .{ "REVERT_HEAD", "REVERTING" },
        .{ "BISECT_LOG", "BISECTING" },
    };

    inline for (states) |state| {
        const state_path = try std.fs.path.join(allocator, &.{ git_dir, state[0] });
        defer allocator.free(state_path);

        if (std.fs.cwd().access(state_path, .{})) |_| {
            return try allocator.dupe(u8, state[1]);
        } else |_| {}
    }

    return error.NoRepoState;
}

fn runGitCommand(allocator: std.mem.Allocator, cwd: []const u8, args: []const []const u8) ![]u8 {
    var argv: std.ArrayList([]const u8) = .{};
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.append(allocator, "-C");
    try argv.append(allocator, cwd);
    try argv.appendSlice(allocator, args);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    // Read stdout using buffered reader
    const stdout = child.stdout.?;
    var read_buffer: [4096]u8 = undefined;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    while (true) {
        const bytes_read = try stdout.read(&read_buffer);
        if (bytes_read == 0) break;
        try result.appendSlice(allocator, read_buffer[0..bytes_read]);
    }

    _ = try child.wait();

    return result.toOwnedSlice(allocator);
}

test "git status parsing" {
    // Basic test placeholder
    try std.testing.expect(true);
}
