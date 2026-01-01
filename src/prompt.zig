const std = @import("std");
const ansi = @import("utils/ansi.zig");
const directory = @import("modules/directory.zig");
const git = @import("modules/git.zig");
const nodejs = @import("modules/nodejs.zig");
const rust = @import("modules/rust.zig");
const java = @import("modules/java.zig");
const golang = @import("modules/golang.zig");
const python = @import("modules/python.zig");
const ruby = @import("modules/ruby.zig");
const docker = @import("modules/docker.zig");
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

const PythonResult = struct {
    info: ?python.PythonInfo = null,
};

const RubyResult = struct {
    info: ?ruby.RubyInfo = null,
};

const DockerResult = struct {
    info: ?docker.DockerInfo = null,
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

fn pythonWorker(result: *PythonResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = python.detect(allocator, cwd);
}

fn rubyWorker(result: *RubyResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = ruby.detect(allocator, cwd);
}

fn dockerWorker(result: *DockerResult, allocator: std.mem.Allocator, cwd: []const u8) void {
    result.info = docker.detect(allocator, cwd);
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
    var python_result = PythonResult{};
    var ruby_result = RubyResult{};
    var docker_result = DockerResult{};

    // LAZY LOADING: First do quick file checks (no subprocess) to detect which projects exist
    // Only spawn threads for projects that are actually detected
    const has_git = !cfg.git_branch.disabled and !cfg.git_status.disabled and git.exists(cwd);
    const has_node = !cfg.nodejs.disabled and nodejs.exists(cwd);
    const has_rust = !cfg.rust.disabled and rust.exists(cwd);
    const has_java = !cfg.java.disabled and java.exists(cwd);
    const has_go = !cfg.golang.disabled and golang.exists(cwd);
    const has_python = !cfg.python.disabled and python.exists(cwd);
    const has_ruby = !cfg.ruby.disabled and ruby.exists(cwd);
    const has_docker = !cfg.docker.disabled and docker.exists(cwd);

    // Count detected projects for parallel execution
    var detected_count: usize = 0;
    if (has_git) detected_count += 1;
    if (has_node) detected_count += 1;
    if (has_rust) detected_count += 1;
    if (has_java) detected_count += 1;
    if (has_go) detected_count += 1;
    if (has_python) detected_count += 1;
    if (has_ruby) detected_count += 1;
    if (has_docker) detected_count += 1;

    if (detected_count >= 2) {
        // Run detected modules in parallel (spawn threads only for detected projects)
        var threads: [8]?std.Thread = .{ null, null, null, null, null, null, null, null };
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

        if (has_python) {
            threads[thread_idx] = std.Thread.spawn(.{}, pythonWorker, .{ &python_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) pythonWorker(&python_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_ruby) {
            threads[thread_idx] = std.Thread.spawn(.{}, rubyWorker, .{ &ruby_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) rubyWorker(&ruby_result, result_allocator, cwd);
            thread_idx += 1;
        }

        if (has_docker) {
            threads[thread_idx] = std.Thread.spawn(.{}, dockerWorker, .{ &docker_result, result_allocator, cwd }) catch null;
            if (threads[thread_idx] == null) dockerWorker(&docker_result, result_allocator, cwd);
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
        if (has_python) pythonWorker(&python_result, result_allocator, cwd);
        if (has_ruby) rubyWorker(&ruby_result, result_allocator, cwd);
        if (has_docker) dockerWorker(&docker_result, result_allocator, cwd);
    }

    return try renderResults(writer, &buffer, result_allocator, cfg, exit_status, duration_ms, git_result, node_result, rust_result, java_result, go_result, python_result, ruby_result, docker_result);
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
    python_result: PythonResult,
    ruby_result: RubyResult,
    docker_result: DockerResult,
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
            if (info.package_version) |pv| allocator.free(pv);
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

    // Render python result
    if (python_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
            if (info.virtualenv) |ve| allocator.free(ve);
        }
        if (try python.renderFromInfo(writer, info)) {
            try writer.writeAll(" ");
        }
    }

    // Render ruby result
    if (ruby_result.info) |info| {
        defer {
            if (info.version) |v| allocator.free(v);
            if (info.gemset) |g| allocator.free(g);
        }
        if (try ruby.renderFromInfo(writer, info)) {
            try writer.writeAll(" ");
        }
    }

    // Render docker result
    if (docker_result.info) |info| {
        defer {
            if (info.context) |c| allocator.free(c);
        }
        if (try docker.renderFromInfo(writer, info)) {
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
