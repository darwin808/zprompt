# zprompt

A fast, minimal shell prompt written in Zig. Like Starship, but smaller and focused.

```
~/projects/my-app on  main [!?] via  v20.11.0 via  v1.75.0
→
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/install.sh | bash
```

Then add to `~/.zshrc`:
```bash
eval "$(zprompt init zsh)"
```

## Language Support

| Language | Status | Detection | Version Source |
|----------|--------|-----------|----------------|
| Node.js | ✅ | `package.json` | `.nvmrc`, `.node-version`, `node --version` |
| Rust | ✅ | `Cargo.toml` | `rustc --version` |
| Go | ✅ | `go.mod` | `.go-version`, `go.mod`, `go version` |
| Java | ✅ | `pom.xml`, `build.gradle` | `.java-version`, `java --version` |
| Python | 🔲 | — | — |
| Ruby | 🔲 | — | — |
| PHP | 🔲 | — | — |
| Elixir | 🔲 | — | — |
| Deno | 🔲 | — | — |
| Bun | 🔲 | — | — |
| Zig | 🔲 | — | — |
| Lua | 🔲 | — | — |
| Kotlin | 🔲 | — | — |
| Swift | 🔲 | — | — |
| C/C++ | 🔲 | — | — |

All enabled modules run **in parallel** — adding more languages doesn't slow things down!

## What it shows

- **Directory** — current path (truncated in git repos)
- **Git** — branch, status indicators, ahead/behind, stash
- **Languages** — version with Nerd Font icons
- **Duration** — for slow commands (>2s)
- **Status** — green/red arrow based on last command

## Performance

| Scenario | zprompt | Starship |
|----------|---------|----------|
| Git only | ~36ms | ~32ms |
| Git + Node + Rust | ~48ms | ~43ms |
| Binary size | 306 KB | 4.6 MB |

## Config

Uses your existing `~/.config/starship.toml`. Disable modules:

```toml
[git_status]
disabled = false

[nodejs]
disabled = false

[rust]
disabled = false

[java]
disabled = false

[golang]
disabled = false

[cmd_duration]
min_time = 2000
```

## Build from source

```bash
git clone https://github.com/darwin808/zprompt
cd zprompt
zig build -Doptimize=ReleaseFast
./zig-out/bin/zprompt --help
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/uninstall.sh | bash
```

---

MIT License
