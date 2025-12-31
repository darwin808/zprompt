# zprompt

A fast, minimal shell prompt. Like Starship, but focused on what matters: **git** and **node**.

```
~/projects/my-app on  main [!3+2] via ⬢ 20.11.0 (pnpm)
❯
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/darwin808/zprompt/main/install.sh | bash
```

Then add to `~/.zshrc`:
```bash
eval "$(zprompt init zsh)"
```

## What it shows

- **Directory** — where you are (with `~` for home)
- **Git** — branch, changes, ahead/behind, stash
- **Node** — version + package manager (npm/yarn/pnpm/bun)
- **Duration** — for slow commands (>2s)
- **Status** — green/red prompt based on last command

## Config

Uses your existing `~/.config/starship.toml`. Disable modules you don't need:

```toml
[git_status]
disabled = false

[nodejs]
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
