const std = @import("std");
const toml = @import("utils/toml.zig");

pub const Config = struct {
    // Format string for the whole prompt
    format: []const u8 = "$directory$git_branch$git_status$nodejs$rust$java$golang$cmd_duration$line_break$character",

    // Directory module
    directory: DirectoryConfig = .{},

    // Git branch module
    git_branch: GitBranchConfig = .{},

    // Git status module
    git_status: GitStatusConfig = .{},

    // Node.js module
    nodejs: NodejsConfig = .{},

    // Rust module
    rust: RustConfig = .{},

    // Java module
    java: JavaConfig = .{},

    // Go module
    golang: GoConfig = .{},

    // Python module
    python: PythonConfig = .{},

    // Ruby module
    ruby: RubyConfig = .{},

    // Docker module
    docker: DockerConfig = .{},

    // Time module
    time: TimeConfig = .{},

    // Username module
    username: UsernameConfig = .{},

    // Hostname module
    hostname: HostnameConfig = .{},

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
    truncation_length: u32 = std.math.maxInt(u32), // effectively no truncation
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

pub const RustConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol($version )]($style)",
    symbol: []const u8 = "🦀 ",
    style: []const u8 = "bold red",
    detect_files: []const []const u8 = &.{"Cargo.toml"},
};

pub const JavaConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol($version )]($style)",
    symbol: []const u8 = "☕ ",
    style: []const u8 = "red dimmed",
    detect_files: []const []const u8 = &.{ "pom.xml", "build.gradle", "build.gradle.kts", ".java-version" },
};

pub const GoConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol($version )]($style)",
    symbol: []const u8 = "🐹 ",
    style: []const u8 = "bold cyan",
    detect_files: []const []const u8 = &.{ "go.mod", "go.sum", ".go-version" },
};

pub const PythonConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [${symbol}${pyenv_prefix}(${version} )(\\($virtualenv\\) )]($style)",
    symbol: []const u8 = "🐍 ",
    style: []const u8 = "bold yellow",
    detect_files: []const []const u8 = &.{ "requirements.txt", "pyproject.toml", "setup.py", "Pipfile", "tox.ini", ".python-version" },
};

pub const RubyConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol($version )]($style)",
    symbol: []const u8 = "💎 ",
    style: []const u8 = "bold red",
    detect_files: []const []const u8 = &.{ "Gemfile", "Rakefile", ".ruby-version" },
};

pub const DockerConfig = struct {
    disabled: bool = false,
    format: []const u8 = "via [$symbol$context]($style) ",
    symbol: []const u8 = "🐳 ",
    style: []const u8 = "bold blue",
    detect_files: []const []const u8 = &.{ "Dockerfile", "docker-compose.yml", "docker-compose.yaml" },
};

pub const TimeConfig = struct {
    disabled: bool = true, // Disabled by default like Starship
    format: []const u8 = "at [$time]($style) ",
    style: []const u8 = "bold yellow",
    time_format: []const u8 = "%T", // HH:MM:SS
    use_12hr: bool = false,
};

pub const UsernameConfig = struct {
    disabled: bool = true, // Only show when SSH or root
    format: []const u8 = "[$user]($style) ",
    style: []const u8 = "bold yellow",
    show_always: bool = false,
};

pub const HostnameConfig = struct {
    disabled: bool = true, // Only show when SSH
    format: []const u8 = "on [$hostname]($style) ",
    style: []const u8 = "bold dimmed green",
    ssh_only: bool = true,
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
    var cfg = Config{};

    // Try starship.toml first
    if (getConfigPath(allocator, "starship.toml")) |path| {
        defer allocator.free(path);
        if (std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024)) |content| {
            defer allocator.free(content);
            applyTomlConfig(&cfg, content, allocator) catch {};
            return cfg;
        } else |_| {}
    } else |_| {}

    // Try zprompt.toml
    if (getConfigPath(allocator, "zprompt.toml")) |path| {
        defer allocator.free(path);
        if (std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024)) |content| {
            defer allocator.free(content);
            applyTomlConfig(&cfg, content, allocator) catch {};
            return cfg;
        } else |_| {}
    } else |_| {}

    return cfg;
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

// Apply TOML config using proper parser
fn applyTomlConfig(config: *Config, content: []const u8, allocator: std.mem.Allocator) !void {
    var root = try toml.parse(allocator, content);
    defer root.deinit();

    // Helper to get string value
    const getString = struct {
        fn call(table: toml.Table, key: []const u8) ?[]const u8 {
            if (table.get(key)) |val| {
                return val.asString();
            }
            return null;
        }
    }.call;

    // Helper to get bool value
    const getBool = struct {
        fn call(table: toml.Table, key: []const u8) ?bool {
            if (table.get(key)) |val| {
                return val.asBool();
            }
            return null;
        }
    }.call;

    // Helper to get int value
    const getInt = struct {
        fn call(comptime T: type, table: toml.Table, key: []const u8) ?T {
            if (table.get(key)) |val| {
                if (val.asInt()) |i| {
                    return @intCast(i);
                }
            }
            return null;
        }
    }.call;

    // Apply directory config
    if (root.getSection("directory")) |section| {
        if (getBool(section, "disabled")) |b| config.directory.disabled = b;
        if (getInt(u32, section, "truncation_length")) |n| config.directory.truncation_length = n;
        if (getBool(section, "truncate_to_repo")) |b| config.directory.truncate_to_repo = b;
        if (getString(section, "style")) |s| config.directory.style = s;
        if (getString(section, "format")) |s| config.directory.format = s;
        if (getString(section, "home_symbol")) |s| config.directory.home_symbol = s;
    }

    // Apply git_branch config
    if (root.getSection("git_branch")) |section| {
        if (getBool(section, "disabled")) |b| config.git_branch.disabled = b;
        if (getInt(u32, section, "truncation_length")) |n| config.git_branch.truncation_length = n;
        if (getString(section, "symbol")) |s| config.git_branch.symbol = s;
        if (getString(section, "style")) |s| config.git_branch.style = s;
        if (getString(section, "format")) |s| config.git_branch.format = s;
        if (getString(section, "truncation_symbol")) |s| config.git_branch.truncation_symbol = s;
    }

    // Apply git_status config
    if (root.getSection("git_status")) |section| {
        if (getBool(section, "disabled")) |b| config.git_status.disabled = b;
        if (getString(section, "format")) |s| config.git_status.format = s;
        if (getString(section, "style")) |s| config.git_status.style = s;
        if (getString(section, "ahead")) |s| config.git_status.ahead = s;
        if (getString(section, "behind")) |s| config.git_status.behind = s;
        if (getString(section, "diverged")) |s| config.git_status.diverged = s;
        if (getString(section, "conflicted")) |s| config.git_status.conflicted = s;
        if (getString(section, "deleted")) |s| config.git_status.deleted = s;
        if (getString(section, "renamed")) |s| config.git_status.renamed = s;
        if (getString(section, "modified")) |s| config.git_status.modified = s;
        if (getString(section, "staged")) |s| config.git_status.staged = s;
        if (getString(section, "untracked")) |s| config.git_status.untracked = s;
        if (getString(section, "stashed")) |s| config.git_status.stashed = s;
    }

    // Apply nodejs config
    if (root.getSection("nodejs")) |section| {
        if (getBool(section, "disabled")) |b| config.nodejs.disabled = b;
        if (getString(section, "format")) |s| config.nodejs.format = s;
        if (getString(section, "symbol")) |s| config.nodejs.symbol = s;
        if (getString(section, "style")) |s| config.nodejs.style = s;
    }

    // Apply rust config
    if (root.getSection("rust")) |section| {
        if (getBool(section, "disabled")) |b| config.rust.disabled = b;
        if (getString(section, "format")) |s| config.rust.format = s;
        if (getString(section, "symbol")) |s| config.rust.symbol = s;
        if (getString(section, "style")) |s| config.rust.style = s;
    }

    // Apply java config
    if (root.getSection("java")) |section| {
        if (getBool(section, "disabled")) |b| config.java.disabled = b;
        if (getString(section, "format")) |s| config.java.format = s;
        if (getString(section, "symbol")) |s| config.java.symbol = s;
        if (getString(section, "style")) |s| config.java.style = s;
    }

    // Apply golang config
    if (root.getSection("golang")) |section| {
        if (getBool(section, "disabled")) |b| config.golang.disabled = b;
        if (getString(section, "format")) |s| config.golang.format = s;
        if (getString(section, "symbol")) |s| config.golang.symbol = s;
        if (getString(section, "style")) |s| config.golang.style = s;
    }

    // Apply python config
    if (root.getSection("python")) |section| {
        if (getBool(section, "disabled")) |b| config.python.disabled = b;
        if (getString(section, "format")) |s| config.python.format = s;
        if (getString(section, "symbol")) |s| config.python.symbol = s;
        if (getString(section, "style")) |s| config.python.style = s;
    }

    // Apply ruby config
    if (root.getSection("ruby")) |section| {
        if (getBool(section, "disabled")) |b| config.ruby.disabled = b;
        if (getString(section, "format")) |s| config.ruby.format = s;
        if (getString(section, "symbol")) |s| config.ruby.symbol = s;
        if (getString(section, "style")) |s| config.ruby.style = s;
    }

    // Apply docker_context config
    if (root.getSection("docker_context")) |section| {
        if (getBool(section, "disabled")) |b| config.docker.disabled = b;
        if (getString(section, "format")) |s| config.docker.format = s;
        if (getString(section, "symbol")) |s| config.docker.symbol = s;
        if (getString(section, "style")) |s| config.docker.style = s;
    }

    // Apply time config
    if (root.getSection("time")) |section| {
        if (getBool(section, "disabled")) |b| config.time.disabled = b;
        if (getString(section, "format")) |s| config.time.format = s;
        if (getString(section, "style")) |s| config.time.style = s;
        if (getString(section, "time_format")) |s| config.time.time_format = s;
        if (getBool(section, "use_12hr")) |b| config.time.use_12hr = b;
    }

    // Apply username config
    if (root.getSection("username")) |section| {
        if (getBool(section, "disabled")) |b| config.username.disabled = b;
        if (getString(section, "format")) |s| config.username.format = s;
        if (getString(section, "style")) |s| config.username.style = s;
        if (getBool(section, "show_always")) |b| config.username.show_always = b;
    }

    // Apply hostname config
    if (root.getSection("hostname")) |section| {
        if (getBool(section, "disabled")) |b| config.hostname.disabled = b;
        if (getString(section, "format")) |s| config.hostname.format = s;
        if (getString(section, "style")) |s| config.hostname.style = s;
        if (getBool(section, "ssh_only")) |b| config.hostname.ssh_only = b;
    }

    // Apply cmd_duration config
    if (root.getSection("cmd_duration")) |section| {
        if (getBool(section, "disabled")) |b| config.cmd_duration.disabled = b;
        if (getInt(u64, section, "min_time")) |n| config.cmd_duration.min_time = n;
        if (getBool(section, "show_milliseconds")) |b| config.cmd_duration.show_milliseconds = b;
        if (getString(section, "format")) |s| config.cmd_duration.format = s;
        if (getString(section, "style")) |s| config.cmd_duration.style = s;
    }

    // Apply character config
    if (root.getSection("character")) |section| {
        if (getBool(section, "disabled")) |b| config.character.disabled = b;
        if (getString(section, "format")) |s| config.character.format = s;
        if (getString(section, "success_symbol")) |s| config.character.success_symbol = s;
        if (getString(section, "error_symbol")) |s| config.character.error_symbol = s;
        if (getString(section, "vimcmd_symbol")) |s| config.character.vimcmd_symbol = s;
    }
}

test "config loading" {
    const allocator = std.testing.allocator;
    const config = try load(allocator);
    try std.testing.expect(!config.directory.disabled);
}
