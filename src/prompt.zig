const std = @import("std");
const ansi = @import("utils/ansi.zig");
const directory = @import("modules/directory.zig");
const git = @import("modules/git.zig");
const nodejs = @import("modules/nodejs.zig");
const rust = @import("modules/rust.zig");
const java = @import("modules/java.zig");
const golang = @import("modules/golang.zig");
const duration = @import("modules/duration.zig");
const config = @import("config.zig");

// Thread result types for parallel detection
const GitResult = struct {
    status: ?git.GitStatus = null,
};

const NodeResult = struct {
    info: ?nodejs.NodeInfo = null,
};

const RustResult = struct {
    info: ?rust.RustInfo = null,
};

const JavaResult = struct {
    info: ?java.JavaInfo = null,
};

const GoResult = struct {
    info: ?golang.GoInfo = null,
};

// Thread worker functions
fn gitWorker(result: *GitResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.status = git.detect(allocator, cwd);
}

fn nodeWorker(result: *NodeResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = nodejs.detect(allocator, cwd);
}

fn rustWorker(result: *RustResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = rust.detect(allocator, cwd);
}

fn javaWorker(result: *JavaResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = java.detect(allocator, cwd);
}

fn goWorker(result: *GoResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = golang.detect(allocator, cwd);
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

    // Initialize all results
    var git_result = GitResult{};
    var node_result = NodeResult{};
    var rust_result = RustResult{};
    var java_result = JavaResult{};
    var go_result = GoResult{};

    // LAZY LOADING: First do quick file checks (no subprocess) to detect which projects exist
    // Only spawn threads for projects that are actually detected
    const has_git = !cfg.git_branch.disabled and !cfg.git_status.disabled and git.exists(cwd);
    const has_node = !cfg.nodejs.disabled and nodejs.exists(cwd);
    const has_rust = !cfg.rust.disabled and rust.exists(cwd);
    const has_java = !cfg.java.disabled and java.exists(cwd);
    const has_go = !cfg.golang.disabled and golang.exists(cwd);

    // Count detected projects for parallel execution
    var detected_count: usize = 0;
    if (has_git) detected_count += 1;
    if (has_node) detected_count += 1;
    if (has_rust) detected_count += 1;
    if (has_java) detected_count += 1;
    if (has_go) detected_count += 1;

    if (detected_count >= 2) {
        // Run detected modules in parallel (spawn threads only for detected projects)
        var threads: [5]?std.Thread = .{ null, null, null, null, null };
        var thread_idx: usize = 0;

        if (has_git) {
            threads[thread_idx] = std.Thread.spawn(.{}, gitWorker, .{ &git_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) gitWorker(&git_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_node) {
            threads[thread_idx] = std.Thread.spawn(.{}, nodeWorker, .{ &node_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) nodeWorker(&node_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_rust) {
            threads[thread_idx] = std.Thread.spawn(.{}, rustWorker, .{ &rust_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) rustWorker(&rust_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_java) {
            threads[thread_idx] = std.Thread.spawn(.{}, javaWorker, .{ &java_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) javaWorker(&java_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_go) {
            threads[thread_idx] = std.Thread.spawn(.{}, goWorker, .{ &go_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) goWorker(&go_result, result_allocator, cwd);
            thread_idx += 1;
        }

        // Wait for all threads to complete
        for (threads) |maybe_thread| {
            if (maybe_thread) |thread| {
                thread.join();
            }
        }
    } else {
        // Run sequentially (only 0-1 projects detected)
        if (has_git) gitWorker(&git_result, result_allocator, cwd);
        if (has_node) nodeWorker(&node_result, result_allocator, cwd);
        if (has_rust) rustWorker(&rust_result, result_allocator, cwd);
        if (has_java) javaWorker(&java_result, result_allocator, cwd);
        if (has_go) goWorker(&go_result, result_allocator, cwd);
    }

    return try renderResults(writer, &buffer, result_allocator, cfg, exit_status, duration_ms, git_result, node_result, rust_result, java_result, go_result);
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
    rust_result: RustResult,
    java_result: JavaResult,
    go_result: GoResult,
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

    // Render rust result
    if (rust_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
        }
        if (try rust.renderFromInfo(writer, info)) {
            try writer.writeAll(" ");
        }
    }

    // Render java result
    if (java_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
        }
        if (try java.renderFromInfo(writer, info)) {
            try writer.writeAll(" ");
        }
    }

    // Render go result
    if (go_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
        }
        if (try golang.renderFromInfo(writer, info)) {
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
