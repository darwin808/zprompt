const std = @import("std");
const ansi = @import("../utils/ansi.zig");

pub const NodeInfo = struct {
    version: ?[]const u8 = null,
    version_source: VersionSource = .none,
    package_manager: ?PackageManager = null,
    package_name: ?[]const u8 = null,
    package_version: ?[]const u8 = null,
};

pub const VersionSource = enum {
    none,
    nvmrc,
    node_version,
    package_json,
    system,
};

pub const PackageManager = enum {
    npm,
    yarn,
    pnpm,
    bun,

    pub fn icon(self: PackageManager) []const u8 {
        return switch (self) {
            .npm => "npm",
            .yarn => "yarn",
            .pnpm => "pnpm",
            .bun => "bun",
        };
    }
};

pub fn render(writer: anytype, allocator: std.mem.Allocator, cwd: []const u8) !bool {
    // Check if this is a Node.js project
    if (!isNodeProject(cwd)) {
        return false;
    }

    const info = try getNodeInfo(allocator, cwd);
    defer {
        if (info.version) |v| allocator.free(v);
        if (info.package_name) |n| allocator.free(n);
        if (info.package_version) |pv| allocator.free(pv);
    }

    var rendered = false;

    // Show package version if available (📦 v1.0.0)
    if (info.package_version) |pkg_ver| {
        try ansi.fg(writer, "is ", ansi.muted_color);
        try ansi.bold(writer, "📦 v", ansi.package_color);
        try ansi.fg(writer, pkg_ver, ansi.package_color);
        rendered = true;
    }

    // Show node version - using Nerd Font icon U+E718
    if (info.version) |ver| {
        if (rendered) try writer.writeAll(" ");
        try ansi.fg(writer, "via ", ansi.muted_color);
        try ansi.bold(writer, "\xee\x9c\x98 v", ansi.node_color); // U+E718 Node.js icon
        try ansi.fg(writer, ver, ansi.node_color);
        rendered = true;
    }

    return rendered;
}

fn isNodeProject(cwd: []const u8) bool {
    // Check for package.json
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const package_path = std.fmt.bufPrint(&path_buf, "{s}/package.json", .{cwd}) catch return false;

    if (std.fs.cwd().access(package_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for node_modules
    const modules_path = std.fmt.bufPrint(&path_buf, "{s}/node_modules", .{cwd}) catch return false;

    if (std.fs.cwd().access(modules_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for .nvmrc
    const nvmrc_path = std.fmt.bufPrint(&path_buf, "{s}/.nvmrc", .{cwd}) catch return false;

    if (std.fs.cwd().access(nvmrc_path, .{})) |_| {
        return true;
    } else |_| {}

    // Check for .node-version
    const nv_path = std.fmt.bufPrint(&path_buf, "{s}/.node-version", .{cwd}) catch return false;

    if (std.fs.cwd().access(nv_path, .{})) |_| {
        return true;
    } else |_| {}

    return false;
}

fn getNodeInfo(allocator: std.mem.Allocator, cwd: []const u8) !NodeInfo {
    var info = NodeInfo{};

    // Get package version from package.json
    info.package_version = getPackageVersion(allocator, cwd) catch null;

    // Priority: .nvmrc > .node-version > system (skip package.json engines - that's constraints, not actual version)
    info.version = getVersionFromNvmrc(allocator, cwd) catch null;
    if (info.version != null) {
        info.version_source = .nvmrc;
    } else {
        info.version = getVersionFromNodeVersion(allocator, cwd) catch null;
        if (info.version != null) {
            info.version_source = .node_version;
        } else {
            // Use actual system node version
            info.version = getSystemNodeVersion(allocator) catch null;
            if (info.version != null) {
                info.version_source = .system;
            }
        }
    }

    // Detect package manager from lockfiles
    info.package_manager = detectPackageManager(cwd);

    return info;
}

fn getPackageVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pkg_path = try std.fmt.bufPrint(&path_buf, "{s}/package.json", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, pkg_path, 1024 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Simple JSON parsing for "version": "x.y.z"
    if (std.mem.indexOf(u8, content, "\"version\"")) |ver_pos| {
        const after_ver = content[ver_pos..];
        if (std.mem.indexOf(u8, after_ver, ":")) |colon_pos| {
            const after_colon = after_ver[colon_pos + 1 ..];
            if (std.mem.indexOf(u8, after_colon, "\"")) |quote_start| {
                const value_start = after_colon[quote_start + 1 ..];
                if (std.mem.indexOf(u8, value_start, "\"")) |quote_end| {
                    const version = value_start[0..quote_end];
                    if (version.len > 0) {
                        return try allocator.dupe(u8, version);
                    }
                }
            }
        }
    }

    return error.VersionNotFound;
}

fn getVersionFromNvmrc(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const nvmrc_path = try std.fmt.bufPrint(&path_buf, "{s}/.nvmrc", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, nvmrc_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    // Clean up version string (remove 'v' prefix if present)
    const version = if (trimmed[0] == 'v') trimmed[1..] else trimmed;
    return try allocator.dupe(u8, version);
}

fn getVersionFromNodeVersion(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const nv_path = try std.fmt.bufPrint(&path_buf, "{s}/.node-version", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, nv_path, 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    const trimmed = std.mem.trim(u8, content, " \t\n\r");
    if (trimmed.len == 0) return error.EmptyFile;

    const version = if (trimmed[0] == 'v') trimmed[1..] else trimmed;
    return try allocator.dupe(u8, version);
}

fn getVersionFromPackageJson(allocator: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const pkg_path = try std.fmt.bufPrint(&path_buf, "{s}/package.json", .{cwd});

    const content = std.fs.cwd().readFileAlloc(allocator, pkg_path, 1024 * 1024) catch {
        return error.FileNotFound;
    };
    defer allocator.free(content);

    // Simple JSON parsing for engines.node
    // Look for "engines" : { "node" : ">=18" }
    if (std.mem.indexOf(u8, content, "\"engines\"")) |engines_pos| {
        const after_engines = content[engines_pos..];
        if (std.mem.indexOf(u8, after_engines, "\"node\"")) |node_pos| {
            const after_node = after_engines[node_pos..];
            // Find the value after the colon
            if (std.mem.indexOf(u8, after_node, ":")) |colon_pos| {
                const after_colon = after_node[colon_pos + 1 ..];
                // Find the quoted value
                if (std.mem.indexOf(u8, after_colon, "\"")) |quote_start| {
                    const value_start = after_colon[quote_start + 1 ..];
                    if (std.mem.indexOf(u8, value_start, "\"")) |quote_end| {
                        const version = value_start[0..quote_end];
                        // Extract version number from constraint (e.g., ">=18.0.0" -> "18.0.0")
                        var cleaned = version;
                        for ([_][]const u8{ ">=", "<=", ">", "<", "^", "~", "=" }) |prefix| {
                            if (std.mem.startsWith(u8, cleaned, prefix)) {
                                cleaned = cleaned[prefix.len..];
                            }
                        }
                        if (cleaned.len > 0) {
                            return try allocator.dupe(u8, cleaned);
                        }
                    }
                }
            }
        }
    }

    return error.EnginesNotFound;
}

fn getSystemNodeVersion(allocator: std.mem.Allocator) ![]u8 {
    var child = std.process.Child.init(&.{ "node", "--version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.NodeNotFound;

    const stdout = child.stdout.?;
    var read_buffer: [256]u8 = undefined;
    const bytes_read = stdout.read(&read_buffer) catch return error.ReadFailed;

    _ = child.wait() catch return error.WaitFailed;

    if (bytes_read == 0) return error.EmptyVersion;

    const trimmed = std.mem.trim(u8, read_buffer[0..bytes_read], " \t\n\r");
    if (trimmed.len == 0) return error.EmptyVersion;

    // Remove 'v' prefix
    const version = if (trimmed[0] == 'v') trimmed[1..] else trimmed;
    return try allocator.dupe(u8, version);
}

fn detectPackageManager(cwd: []const u8) ?PackageManager {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Check in order of specificity
    // bun.lockb
    const bun_lock = std.fmt.bufPrint(&path_buf, "{s}/bun.lockb", .{cwd}) catch return null;
    if (std.fs.cwd().access(bun_lock, .{})) |_| {
        return .bun;
    } else |_| {}

    // pnpm-lock.yaml
    const pnpm_lock = std.fmt.bufPrint(&path_buf, "{s}/pnpm-lock.yaml", .{cwd}) catch return null;
    if (std.fs.cwd().access(pnpm_lock, .{})) |_| {
        return .pnpm;
    } else |_| {}

    // yarn.lock
    const yarn_lock = std.fmt.bufPrint(&path_buf, "{s}/yarn.lock", .{cwd}) catch return null;
    if (std.fs.cwd().access(yarn_lock, .{})) |_| {
        return .yarn;
    } else |_| {}

    // package-lock.json
    const npm_lock = std.fmt.bufPrint(&path_buf, "{s}/package-lock.json", .{cwd}) catch return null;
    if (std.fs.cwd().access(npm_lock, .{})) |_| {
        return .npm;
    } else |_| {}

    return null;
}

test "package manager detection" {
    // Basic placeholder test
    try std.testing.expect(true);
}
