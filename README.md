# zprompt

A blazingly fast shell prompt written in Zig. Drop-in Starship replacement.

```
~/projects/my-app on  main [!?] is 📦 v1.0.0 via  v20.11.0
→
```

## Why zprompt?

| Metric | zprompt | Starship | Improvement |
|--------|---------|----------|-------------|
| Speed (cached) | **2ms** | 30ms | 14x faster |
| Speed (cold) | **20ms** | 30ms | 1.5x faster |
| Memory | **4.8 MB** | 30 MB | 6x smaller |
| Binary | **306 KB** | 4.6 MB | 15x smaller |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/install.sh | bash
```

Add to your shell config:

```bash
# ~/.zshrc
eval "$(zprompt init zsh)"

# ~/.bashrc
eval "$(zprompt init bash)"

# ~/.config/fish/config.fish
zprompt init fish | source

# PowerShell
Invoke-Expression (&zprompt init powershell)
```

## Features

- **Multi-shell**: zsh, bash, fish, powershell
- **Parallel detection**: All modules run concurrently
- **Smart caching**: Version detection cached for 1 hour
- **Native git**: Parses `.git/index` directly (no subprocess)
- **Starship config**: Uses your existing `~/.config/starship.toml`

## Modules

| Module | Detection | Version Source |
|--------|-----------|----------------|
| Git | `.git/` | Native index parsing |
| Node.js | `package.json` | `.nvmrc`, `.node-version`, cache |
| Rust | `Cargo.toml` | `rust-toolchain.toml`, cache |
| Python | `requirements.txt`, `pyproject.toml` | `.python-version`, cache |
| Ruby | `Gemfile` | `.ruby-version`, cache |
| Go | `go.mod` | `.go-version`, `go.mod` |
| Java | `pom.xml`, `build.gradle` | `.java-version`, cache |
| Docker | `Dockerfile`, `docker-compose.yml` | Docker context |

## What it shows

- **Directory** — current path (truncated in git repos)
- **Git** — branch + status (`!` modified, `?` untracked, `+` staged)
- **Package** — version from package.json/Cargo.toml (📦 v1.0.0)
- **Language** — runtime version with Nerd Font icons
- **Duration** — for slow commands (>2s)
- **Status** — green/red arrow based on exit code

## Config

Uses `~/.config/starship.toml`:

```toml
[git_status]
disabled = false

[nodejs]
disabled = false

[rust]
disabled = false

[python]
disabled = false

[cmd_duration]
min_time = 2000  # Show duration for commands >2s
```

## Build from source

Requires Zig 0.14+

```bash
git clone https://github.com/darwin808/zprompt
cd zprompt
zig build -Doptimize=ReleaseFast
cp zig-out/bin/zprompt ~/.local/bin/
```

## How it's fast

1. **No runtime** — Zig compiles to native code with no GC
2. **Parallel execution** — All module detection runs in threads
3. **Smart caching** — Version lookups cached in `~/.cache/zprompt/`
4. **Native git** — Reads `.git/index` directly instead of `git status`
5. **Lazy loading** — Only spawns threads for detected project types

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/uninstall.sh | bash
```

---

MIT License
