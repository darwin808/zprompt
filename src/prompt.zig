const std = @import("std");
const ansi = @import("utils/ansi.zig");
const directory = @import("modules/directory.zig");
const git = @import("modules/git.zig");
const nodejs = @import("modules/nodejs.zig");
const duration = @import("modules/duration.zig");
const config = @import("config.zig");

// Thread result types for parallel detection
const GitResult = struct {
    status: ?git.GitStatus = null,
};

const NodeResult = struct {
    info: ?nodejs.NodeInfo = null,
};

// Thread worker functions
fn gitWorker(result: *GitResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.status = git.detect(allocator, cwd);
}

fn nodeWorker(result: *NodeResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = nodejs.detect(allocator, cwd);
}

/// Render prompt with parallel detection
/// result_allocator: thread-safe allocator for parallel work and final result (GPA)
/// temp_allocator: arena allocator for temporary non-threaded work
pub fn render(result_allocator: std.mem.Allocator, temp_allocator: std.mem.Allocator, cfg: config.Config, exit_status: u8, duration_ms: u64) ![]u8 {
    var buffer: std.ArrayList(u8) = .{};
    errdefer buffer.deinit(result_allocator);

    const writer = buffer.writer(result_allocator);

    // Get current directory
    const cwd = std.fs.cwd().realpathAlloc(temp_allocator, ".") catch {
        // Can't get cwd - return minimal prompt
        try ansi.bold(writer, "→", ansi.error_color);
        try writer.writeAll(" ");
        return buffer.toOwnedSlice(result_allocator);
    };
    // Note: cwd freed when arena is destroyed, no defer needed

    // Directory (fast, run synchronously)
    if (!cfg.directory.disabled) {
        try directory.render(writer, temp_allocator, cwd);
        try writer.writeAll(" ");
    }

    // Parallel detection for git and nodejs
    var git_result = GitResult{};
    var node_result = NodeResult{};

    const run_git = !cfg.git_branch.disabled and !cfg.git_status.disabled;
    const run_node = !cfg.nodejs.disabled;

    if (run_git and run_node) {
        // Both enabled - run in parallel using thread-safe allocator
        const git_thread = std.Thread.spawn(.{}, gitWorker, .{ &git_result, result_allocator, cwd }) catch {
            // Fallback to sequential if thread spawn fails
            gitWorker(&git_result, result_allocator, cwd);
            nodeWorker(&node_result, result_allocator, cwd);
            return try renderResults(writer, &buffer, result_allocator, cfg, exit_status, duration_ms, git_result, node_result);
        };

        const node_thread = std.Thread.spawn(.{}, nodeWorker, .{ &node_result, result_allocator, cwd }) catch {
            // Join git thread first, then run node sequentially
            git_thread.join();
            nodeWorker(&node_result, result_allocator, cwd);
            return try renderResults(writer, &buffer, result_allocator, cfg, exit_status, duration_ms, git_result, node_result);
        };

        // Wait for both threads to complete
        git_thread.join();
        node_thread.join();
    } else if (run_git) {
        gitWorker(&git_result, result_allocator, cwd);
    } else if (run_node) {
        nodeWorker(&node_result, result_allocator, cwd);
    }

    return try renderResults(writer, &buffer, result_allocator, cfg, exit_status, duration_ms, git_result, node_result);
}

fn renderResults(
    writer: anytype,
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    cfg: config.Config,
    exit_status: u8,
    duration_ms: u64,
    git_result: GitResult,
    node_result: NodeResult,
) ![]u8 {
    // Render git result
    if (git_result.status) |status| {
        defer {
            if (status.branch) |b| allocator.free(b);
            if (status.repo_state) |s| allocator.free(s);
        }
        try git.renderFromStatus(writer, status);
        try writer.writeAll(" ");
    }

    // Render node result
    if (node_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
            if (info.package_name) |n| allocator.free(n);
            if (info.package_version) |pv| allocator.free(pv);
        }
        if (try nodejs.renderFromInfo(writer, info)) {
            try writer.writeAll(" ");
        }
    }

    // Duration (fast, run synchronously)
    if (!cfg.cmd_duration.disabled) {
        if (try duration.renderWithConfig(writer, duration_ms, cfg.cmd_duration.min_time)) {
            try writer.writeAll(" ");
        }
    }

    // Newline before character
    try writer.writeAll("\n");

    // Exit status character
    if (!cfg.character.disabled) {
        if (exit_status == 0) {
            try ansi.bold(writer, "→", ansi.success_color);
        } else {
            try ansi.bold(writer, "→", ansi.error_color);
        }
        try writer.writeAll(" ");
    }

    return buffer.toOwnedSlice(allocator);
}

test "render basic prompt" {
    const allocator = std.testing.allocator;
    const cfg = config.Config{};
    const result = try render(allocator, allocator, cfg, 0, 0);
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}
