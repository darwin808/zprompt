const std = @import("std");

pub const Config = struct {
    // Format string for the whole prompt
    format: []const u8 = "$directory$git_branch$git_status$nodejs$cmd_duration$line_break$character",

    // Directory module
    directory: DirectoryConfig = .{},

    // Git branch module
    git_branch: GitBranchConfig = .{},

    // Git status module
    git_status: GitStatusConfig = .{},

    // Node.js module
    nodejs: NodejsConfig = .{},

    // Command duration module
    cmd_duration: CmdDurationConfig = .{},

    // Character (prompt symbol) module
    character: CharacterConfig = .{},
};

pub const DirectoryConfig = struct {
    disabled: bool = false,
    truncation_length: u32 = 3,
    truncate_to_repo: bool = true,
    format: []const u8 = "[$path]($style) ",
    style: []const u8 = "bold cyan",
    home_symbol: []const u8 = "~",
};

pub const GitBranchConfig = struct {
    disabled: bool = false,
    format: []const u8 = "on [$symbol$branch]($style) ",
    symbol: []const u8 = " ",
    style: []const u8 = "bold purple",
    truncation_length: u32 = 9223372036854775807, // max u64, effectively no truncation
    truncation_symbol: []const u8 = "…",
};

pub const GitStatusConfig = struct {
    disabled: bool = false,
    format: []const u8 = "[\\[$all_status$ahead_behind\\]]($style) ",
    style: []const u8 = "bold red",
    ahead: []const u8 = "⇡",
    behind: []const u8 = "⇣",
    diverged: []const u8 = "⇕",
    conflicted: []const u8 = "=",
    deleted: []const u8 = "✘",
    renamed: []const u8 = "»",
    modified: []const u8 = "!",
    staged: []const u8 = "+",
    untracked: []const u8 = "?",
    stashed: []const u8 = "$",
};

pub const NodejsConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol($version )]($style)",
    symbol: []const u8 = "⬢ ",
    style: []const u8 = "bold green",
    detect_extensions: []const []const u8 = &.{ "js", "mjs", "cjs", "ts", "mts", "cts" },
    detect_files: []const []const u8 = &.{ "package.json", ".node-version", ".nvmrc" },
    detect_folders: []const []const u8 = &.{"node_modules"},
};

pub const CmdDurationConfig = struct {
    disabled: bool = false,
    min_time: u64 = 2000, // milliseconds
    format: []const u8 = "took [$duration]($style) ",
    style: []const u8 = "bold yellow",
    show_milliseconds: bool = false,
};

pub const CharacterConfig = struct {
    disabled: bool = false,
    format: []const u8 = "$symbol ",
    success_symbol: []const u8 = "[❯](bold green)",
    error_symbol: []const u8 = "[❯](bold red)",
    vimcmd_symbol: []const u8 = "[❮](bold green)",
};

pub fn load(allocator: std.mem.Allocator) !Config {
    var config = Config{};

    // Try to load from config files
    const config_paths = [_][]const u8{
        getConfigPath(allocator, "starship.toml") catch null,
        getConfigPath(allocator, "zprompt.toml") catch null,
    };

    for (config_paths) |maybe_path| {
        if (maybe_path) |path| {
            defer allocator.free(path);

            const content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch continue;
            defer allocator.free(content);

            parseToml(&config, content, allocator) catch continue;
            break;
        }
    }

    return config;
}

fn getConfigPath(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    // Check XDG_CONFIG_HOME first
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg_config| {
        return try std.fs.path.join(allocator, &.{ xdg_config, filename });
    }

    // Fall back to ~/.config
    if (std.posix.getenv("HOME")) |home| {
        return try std.fs.path.join(allocator, &.{ home, ".config", filename });
    }

    return error.NoConfigPath;
}

// Simple TOML parser for the subset we need
fn parseToml(config: *Config, content: []const u8, allocator: std.mem.Allocator) !void {
    _ = allocator;

    var current_section: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Section header
        if (trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            current_section = trimmed[1 .. trimmed.len - 1];
            continue;
        }

        // Key = value
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = std.mem.trim(u8, trimmed[0..eq_pos], " \t");
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            // Parse value
            if (current_section) |section| {
                applyConfig(config, section, key, value);
            }
        }
    }
}

fn applyConfig(config: *Config, section: []const u8, key: []const u8, value: []const u8) void {
    // Parse boolean
    const parseBool = struct {
        fn call(v: []const u8) ?bool {
            if (std.mem.eql(u8, v, "true")) return true;
            if (std.mem.eql(u8, v, "false")) return false;
            return null;
        }
    }.call;

    // Parse integer
    const parseInt = struct {
        fn call(comptime T: type, v: []const u8) ?T {
            return std.fmt.parseInt(T, v, 10) catch null;
        }
    }.call;

    if (std.mem.eql(u8, section, "directory")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.directory.disabled = b;
        } else if (std.mem.eql(u8, key, "truncation_length")) {
            if (parseInt(u32, value)) |n| config.directory.truncation_length = n;
        } else if (std.mem.eql(u8, key, "truncate_to_repo")) {
            if (parseBool(value)) |b| config.directory.truncate_to_repo = b;
        }
    } else if (std.mem.eql(u8, section, "git_branch")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.git_branch.disabled = b;
        } else if (std.mem.eql(u8, key, "truncation_length")) {
            if (parseInt(u32, value)) |n| config.git_branch.truncation_length = n;
        }
    } else if (std.mem.eql(u8, section, "git_status")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.git_status.disabled = b;
        }
    } else if (std.mem.eql(u8, section, "nodejs")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.nodejs.disabled = b;
        }
    } else if (std.mem.eql(u8, section, "cmd_duration")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.cmd_duration.disabled = b;
        } else if (std.mem.eql(u8, key, "min_time")) {
            if (parseInt(u64, value)) |n| config.cmd_duration.min_time = n;
        } else if (std.mem.eql(u8, key, "show_milliseconds")) {
            if (parseBool(value)) |b| config.cmd_duration.show_milliseconds = b;
        }
    } else if (std.mem.eql(u8, section, "character")) {
        if (std.mem.eql(u8, key, "disabled")) {
            if (parseBool(value)) |b| config.character.disabled = b;
        }
    }
}

test "config loading" {
    const allocator = std.testing.allocator;
    const config = try load(allocator);
    try std.testing.expect(!config.directory.disabled);
}
