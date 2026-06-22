# Git Worktree Configuration

Configuration reference for `git-wt` 0.29.0 and native `git worktree`.

## Configuration Levels

Prefer repository-local settings when a convention should be attached to one repository.

```bash
git config --local wt.basedir ".worktrees"
git config --global wt.basedir ".worktrees"
```

## git-wt Configuration

`git-wt` reads Git config. Command-line flags override config for one invocation.

### wt.basedir

Base directory for generated worktrees.

```bash
git config wt.basedir ".worktrees"
git config wt.basedir "../{gitroot}-wt"
```

Default: `.wt`.

`{gitroot}` expands to the repository root directory name.

### wt.copyignored

Copy ignored files, such as `.env`, to newly created worktrees.

```bash
git config wt.copyignored true
```

Default: `false`.

### wt.copyuntracked

Copy untracked files to newly created worktrees.

```bash
git config wt.copyuntracked true
```

Default: `false`.

### wt.copymodified

Copy modified tracked files to newly created worktrees.

```bash
git config wt.copymodified true
```

Default: `false`.

### wt.copy

Always copy files matching gitignore-style patterns.

```bash
git config --add wt.copy "*.code-workspace"
git config --add wt.copy ".vscode/"
git config --add wt.copy ".env.local"
```

Use repeated `--add` entries. This is useful for editor files and local env files that should follow new worktrees.

### wt.nocopy

Exclude files matching gitignore-style patterns from copying.

```bash
git config --add wt.nocopy "*.log"
git config --add wt.nocopy "vendor/"
```

If a file matches both `wt.copy` and `wt.nocopy`, `wt.nocopy` takes precedence.

### wt.symlink

Symlink matching top-level directories instead of copying them.

```bash
git config --add wt.symlink "node_modules/"
```

This can be faster than copying, but changes affect all worktrees that share the symlinked directory.

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
git config --add wt.deletehook "git status --short"
```

Hooks run in the worktree directory before removal. They do not run when deleting a branch without a worktree.

### wt.remover

Custom command used to remove the worktree directory.

```bash
git config wt.remover "trash-put"
```

The worktree path is passed as an argument. After the command completes, `git worktree prune` runs automatically.

### wt.nocd

Controls whether `git wt` changes directory to the selected worktree.

```bash
git config wt.nocd create
```

Supported values:

- `true` or `all`: never change directory
- `create`: do not change directory when creating worktrees, but allow switching to existing worktrees
- `false`: change directory normally

Default: `false`.

### wt.relative

Append the current subdirectory path to the output path.

```bash
git config wt.relative true
```

Default: `false`.

## Native Git Configuration

### worktree.guessRemote

Native Git can guess a remote branch when adding a worktree for an existing branch name.

```bash
git config worktree.guessRemote true
```

Use this for native `git worktree add` flows. It is separate from `git-wt`'s copy, hook, and directory behavior.

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

## Recommended Local Setup

```bash
git config --local wt.basedir ".worktrees"
git config --local wt.nocd create
```

Add `wt.copy` only for specific local files that should be copied to every new worktree.

```bash
git config --add wt.copy ".env.local"
```

## Troubleshooting Configuration

```bash
git config --get-regexp '^wt\.'
git config --show-origin wt.basedir
git config --local --unset wt.basedir
git config --local --remove-section wt
```

Use the diagnostic script when available:

```bash
scripts/check-worktree-config.sh
```

## See Also

- [Command Reference](git-wt-commands.md)
- [Workflow Patterns](workflows.md)
- [Troubleshooting](troubleshooting.md)
