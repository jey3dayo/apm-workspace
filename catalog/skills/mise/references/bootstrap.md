# mise bootstrap — Declarative Machine Setup

`mise bootstrap` sets up a machine for the current config in one command: OS packages, git repos, dotfiles, shell activation, macOS defaults, LaunchAgents, systemd user services, login shell, `[tools]`, and a final custom task. Introduced in v2026.6.6, completed end-to-end in v2026.6.14. Still gated behind `settings.experimental = true` (verified on 2026.7.3: commands error with "mise bootstrap is experimental" without it) — set it in config or `mise settings experimental=true` before running. Older mise binaries emit `unknown field: bootstrap` warnings — upgrade mise first.

Declarative sections converge idempotently: already-installed packages, matching dotfiles, repos at the requested ref, and defaults already set are skipped. The custom `[tasks.bootstrap]` hook runs every time — its idempotency is your responsibility.

## Config sections

Keys MUST be nested tables (`[bootstrap.packages]`, `[tasks.bootstrap]`); flat `bootstrap = ...` keys are rejected.

| Section                            | Role                                                      |
| ---------------------------------- | --------------------------------------------------------- |
| `[bootstrap.packages]`             | OS packages via system package managers                   |
| `[bootstrap.brew.taps]`            | Third-party Homebrew taps                                 |
| `[bootstrap.repos]`                | Git repos cloned before dotfiles (pre/post hooks)         |
| `[dotfiles]`                       | Whole-file dotfiles and managed edits                     |
| `[bootstrap.mise_shell_activate]`  | Shell activation snippet (bash/zsh/fish)                  |
| `[bootstrap.macos.defaults]`       | macOS user defaults (with drift reporting)                |
| `[bootstrap.macos.launchd.agents]` | macOS user LaunchAgents (`dev.mise.<name>.plist`)         |
| `[bootstrap.linux.systemd.units]`  | Linux systemd user services                               |
| `[bootstrap.user]`                 | Login shell etc. (`chsh` convergence)                     |
| `[bootstrap.hooks.*]`              | Commands at named phases (pre/post-packages, ... + final) |
| `[tools]` / `[tasks.bootstrap]`    | Versioned dev tools / imperative final setup task         |

Execution order: packages → repos → dotfiles → shell activation → macOS defaults → launchd → systemd → user → tools → bootstrap task → final hooks. Hooks run in the current process env; commands needing `[tools]` must go through `mise exec`.

## Packages: backends and syntax

```toml
[bootstrap.packages]
"apt:build-essential" = "latest"
"brew:postgresql@17" = "latest"
"brew-cask:firefox" = "latest"
"mas:1502839586" = "latest"
```

- Backends: `apk`, `apt`, `dnf`, `pacman`, `brew` (formulae), `brew-cask`, `mas`. No winget.
- Version pinning is name-side only (`postgresql@17`); values are always `"latest"`.
- `brew-cask` is native — installs from cask API metadata without requiring a local Homebrew install. pkg artifacts run via `sudo installer` (pkgutil receipts tracked); binary artifacts are staged in the Caskroom and symlinked under the Homebrew prefix.
- `mas` requires the user to already be signed into the Mac App Store.

## CLI surface

| Command                                          | Behavior                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| `mise bootstrap [--yes] [--dry-run] [--update]`  | Full run; `--skip <part>` / `--only <part>` (mutually exclusive)      |
| `mise bootstrap status [--json] [--missing]`     | One report across all surfaces (alias `ls`)                           |
| `mise bootstrap packages apply / use / status`   | Install missing / add declaration / report drift                      |
| `mise bootstrap packages upgrade [-m <manager>]` | Refresh metadata, upgrade installed packages (skips uninstalled ones) |
| `mise bootstrap packages import [--all] [-n]`    | `brew bundle dump` equivalent — see below                             |
| `mise bootstrap packages prune [--dry-run]`      | Remove undeclared formulae — see safety below                         |
| `mise bootstrap packages brew tap/untap`         | Edit `[bootstrap.brew.taps]`                                          |
| `mise dotfiles add / apply / edit / status`      | Dotfiles operations                                                   |
| `mise bootstrap shell apply / status`            | Shell activation snippet                                              |

Dotfiles conflicts are refused by default; `--force-dotfiles` overrides explicitly.

## import scope

- Brew formulae ONLY — no cask or mas import. Default imports formulae installed on request (top-level); `--all` includes dependencies. Flags: `-g/--global`, `-p/--path`, `-n/--dry-run`, `-m/--manager`.

## prune safety

- Opt-in, separate command — never automatic on `bootstrap`.
- Prefix-inventory based: can remove ANY linked formula outside the closure resolved from the current config plus trusted tracked configs — including formulae you installed manually and never declared.
- Brew formulae only (casks/mas not pruned).
- ALWAYS run `--dry-run` first and review the removal list; a sparse `[bootstrap.packages]` makes prune aggressive. Interactive confirmation by default; `--yes` skips it.

## Migration from Brewfile

| Concern    | brew bundle                   | mise bootstrap packages                  |
| ---------- | ----------------------------- | ---------------------------------------- |
| Manifest   | Brewfile                      | mise.toml (unified with tools/tasks/env) |
| Dump       | `brew bundle dump`            | `packages import` (formulae only)        |
| Cleanup    | `brew bundle cleanup --force` | `packages prune` (formulae only)         |
| Cask / mas | Yes                           | Yes (cask without Homebrew itself)       |
| Linux pkgs | No                            | apt/apk/dnf/pacman                       |

Path: `packages import --dry-run` for formulae, hand-translate casks/mas entries (import doesn't cover them), verify with `packages status --missing`, then retire the Brewfile. Community migration precedent is essentially nil (feature is from June 2026) — treat as early adoption and pin a recent mise version.

## Real-world example

`~/.config/mise/config.toml` (OS-independent `[dotfiles]`, `[tasks.bootstrap]`) and `config.macos.toml` (macOS-only `[bootstrap.packages]`, copy-mode `[dotfiles]` entries, `[bootstrap.macos.launchd.agents]`; loaded via `MISE_ENV=macos` set on Darwin) show the environment-file split from `references/task-config-includes.md` applied to bootstrap sections. Keep OS-specific bootstrap sections out of configs shared with other OSes.
