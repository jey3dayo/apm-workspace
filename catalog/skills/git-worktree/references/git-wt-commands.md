# git-wt Command Reference

Command reference for `git-wt` 0.29.0.

## Overview

`git-wt` is a Git subcommand that makes `git worktree` operations shorter. Use it for day-to-day local worktree operations, and use native `git worktree` for low-level Git cleanup, locked worktrees, or portable automation.

## Usage

```bash
git wt [branch|worktree|path] [start-point] [flags]
```

## Common Operations

### List Worktrees

```bash
git wt
git wt --json
```

With no arguments, `git wt` lists worktrees.

### Switch or Create

```bash
git wt feature/user-auth
git wt feature/user-auth origin/main
```

If the named worktree already exists, `git wt` switches to it when shell integration is enabled. Otherwise it creates a worktree and branch. The optional second argument is the start point.

### Create With a Different Branch Name

```bash
git wt -b feature/user-auth user-auth
```

`-b, --branch <branch>` creates or uses a branch name that differs from the worktree directory name.

### Delete

```bash
git wt -d feature/user-auth
git wt -D feature/user-auth
```

`-d, --delete` safely deletes worktrees and branches only when the branch is merged. `-D, --force-delete` forces deletion.

The default branch, such as `main` or `master`, is protected from accidental deletion. Use `--allow-delete-default` only when that is intentional.

### Rename or Move

```bash
git wt -m old-name new-name
git wt -M old-name new-name
```

`-m, --move` safely renames the worktree directory and branch. `-M, --force-move` allows overwriting an existing branch and moving dirty or locked worktrees.

## Flags

| Flag                     | Meaning                                                             |
| ------------------------ | ------------------------------------------------------------------- |
| `--allow-delete-default` | Allow deletion of the default branch                                |
| `--basedir <dir>`        | Override `wt.basedir` for one invocation                            |
| `-b, --branch <branch>`  | Use a branch name different from the worktree directory name        |
| `--copy <pattern>`       | Always copy files matching a gitignore-style pattern; repeatable    |
| `--copyignored`          | Copy ignored files                                                  |
| `--copymodified`         | Copy modified files                                                 |
| `--copyuntracked`        | Copy untracked files                                                |
| `-d, --delete`           | Safe-delete worktree and branch                                     |
| `--deletehook <command>` | Run a command before deleting a worktree; repeatable                |
| `-D, --force-delete`     | Force-delete worktree and branch                                    |
| `-M, --force-move`       | Force-rename worktree directory and branch                          |
| `--hook <command>`       | Run a command after creating a worktree; repeatable                 |
| `--init <shell>`         | Output shell integration for `bash`, `zsh`, `fish`, or `powershell` |
| `--json`                 | Output JSON                                                         |
| `-m, --move`             | Safe-rename worktree directory and branch                           |
| `--nocd`                 | Print the worktree path without changing directory                  |
| `--nocopy <pattern>`     | Exclude files matching a gitignore-style pattern; repeatable        |
| `--relative`             | Append the current subdirectory path to the output path             |
| `--remover <command>`    | Use a custom remover for the worktree directory                     |
| `--symlink <pattern>`    | Symlink matching top-level directories instead of copying           |
| `-v, --version`          | Show version                                                        |

## Configuration

`git-wt` uses Git config. Flags override config values for a single invocation.

### wt.basedir

Worktree base directory.

```bash
git config wt.basedir ".worktrees"
git config wt.basedir "../{gitroot}-wt"
```

Default: `.wt`. The `{gitroot}` template variable expands to the repository root directory name.

### wt.copyignored

Copy ignored files, such as `.env`, to new worktrees.

```bash
git config wt.copyignored true
```

Default: `false`.

### wt.copyuntracked

Copy untracked files to new worktrees.

```bash
git config wt.copyuntracked true
```

Default: `false`.

### wt.copymodified

Copy modified files to new worktrees.

```bash
git config wt.copymodified true
```

Default: `false`.

### wt.copy

Patterns for files to always copy, even if ignored.

```bash
git config --add wt.copy "*.code-workspace"
git config --add wt.copy ".vscode/"
```

Patterns use gitignore syntax and can be repeated.

### wt.nocopy

Patterns for files to exclude from copying.

```bash
git config --add wt.nocopy "*.log"
git config --add wt.nocopy "vendor/"
```

When a file matches both `wt.copy` and `wt.nocopy`, `wt.nocopy` wins.

### wt.symlink

Patterns for top-level directories to symlink instead of copy.

```bash
git config --add wt.symlink "node_modules/"
```

Symlinking is faster, but changes affect all worktrees sharing that directory.

### wt.hook

Commands to run after creating a new worktree.

```bash
git config --add wt.hook "npm install"
git config --add wt.hook "go generate ./..."
```

Hooks run in the new worktree directory. They do not run when switching to an existing worktree.

### wt.deletehook

Commands to run before deleting a worktree.

```bash
git config --add wt.deletehook "git push origin --delete $(git branch --show-current)"
```

Hooks run in the worktree directory before removal. They do not run when deleting a branch without a worktree.

### wt.remover

Custom command for removing the worktree directory.

```bash
git config wt.remover "trash-put"
```

The worktree path is passed as an argument. After the command completes, `git worktree prune` runs automatically.

### wt.nocd

Controls whether `git wt` changes directory to the worktree.

```bash
git config wt.nocd create
```

Supported values:

- `true` or `all`: never change directory
- `create`: do not change directory only when creating worktrees
- `false`: always change directory

Default: `false`.

### wt.relative

Append the current subdirectory path to the output path.

```bash
git config wt.relative true
```

Default: `false`.

## Shell Integration

Shell integration enables worktree switching and completion.

```bash
# bash
eval "$(git-wt --init bash)"

# zsh
eval "$(git-wt --init zsh)"

# fish
git-wt --init fish | source

# powershell
Invoke-Expression (git-wt --init powershell | Out-String)
```

## Comparison With Native git worktree

| Use case                                           | Prefer               |
| -------------------------------------------------- | -------------------- |
| Local development worktree creation and switching  | `git wt`             |
| Copying ignored or local files into a new worktree | `git wt`             |
| Running setup hooks after creating a worktree      | `git wt`             |
| Portable automation and CI scripts                 | `git worktree`       |
| Pruning stale Git metadata                         | `git worktree prune` |
| Locked worktree diagnosis or repair                | `git worktree`       |

## See Also

- [Configuration Options](configuration.md)
- [Workflow Patterns](workflows.md)
- [Troubleshooting](troubleshooting.md)
