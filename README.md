# zprompt

A minimal, fast shell prompt written in Zig. Drop-in replacement for Starship with focused scope.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/install.sh | bash
```

Then add to your `~/.zshrc`:

```bash
eval "$(zprompt init zsh)"
```

## Features

- **Git**: branch, status (modified/staged/untracked/deleted), ahead/behind, stash count, repo state
- **Node.js**: version detection (`.nvmrc`, `.node-version`, `package.json`, system)
- **Package Manager**: npm/yarn/pnpm/bun detection via lockfiles
- **Directory**: smart path truncation with `~` replacement
- **Duration**: shows command execution time (>2s)
- **Config**: reads `~/.config/starship.toml` (compatible subset)

## Configuration

zprompt reads your existing `~/.config/starship.toml`. Supported options:

```toml
[directory]
disabled = false
truncation_length = 3

[git_branch]
disabled = false

[git_status]
disabled = false

[nodejs]
disabled = false

[cmd_duration]
disabled = false
min_time = 2000  # milliseconds

[character]
disabled = false
```

## Building from Source

```bash
# Requires Zig 0.13+
git clone https://github.com/darwin808/zprompt
cd zprompt
zig build -Doptimize=ReleaseFast
./zig-out/bin/zprompt --help
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/uninstall.sh | bash
```

## License

MIT
