# Git Worktree Troubleshooting

Comprehensive troubleshooting guide for common Git worktree issues and their solutions.

## Common Issues

### Issue: Branch Already Checked Out

### Symptom

```
fatal: 'feature/user-auth' is already checked out at '/path/to/repo/.worktrees/user-auth'
```

### Cause

### Solutions

#### Option 1: Switch to existing worktree

```bash
# List worktrees to find the existing one
git wt

# Switch to existing worktree
git wt feature/user-auth
# or
cd .worktrees/user-auth
```

#### Option 2: Remove existing worktree

```bash
# Remove the existing worktree
git wt -d feature/user-auth

# Create new worktree
git wt feature/user-auth
```

#### Option 3: Use different branch name

```bash
# Create with a different branch name
git wt feature/user-auth-v2
```

### Prevention

### Issue: Worktree Directory Deleted Manually

### Symptom

```
# git wt shows worktree, but directory doesn't exist
fatal: '/path/to/repo/.worktrees/deleted' does not exist
```

### Cause

### Solution

```bash
# Prune stale worktree metadata
git worktree prune -v

# Verify cleanup
git wt
```

### If prune doesn't work

Manual metadata deletion is destructive. Confirm the exact path and get explicit user approval before running it.

```bash
# Manual cleanup
rm -rf .git/worktrees/deleted

# Verify
git wt
```

### Prevention

### Issue: Locked Worktree Cannot Be Removed

### Symptom

```
fatal: 'feature/locked' is locked; reason: Long-running build
```

### Cause

### Solution

```bash
# Unlock worktree
git worktree unlock .worktrees/locked

# Remove worktree
git wt -d feature/locked
```

### Force removal

Manual lock deletion is destructive. Confirm the exact path and get explicit user approval before running it.

```bash
# Remove lock file manually
rm .git/worktrees/locked/locked

# Remove worktree
git wt -d feature/locked
```

### Prevention

### Issue: Uncommitted Changes Prevent Removal

### Symptom

```
error: Worktree contains uncommitted changes
fatal: Cannot remove worktree 'feature/work-in-progress'
```

### Cause

### Solutions

#### Option 1: Commit changes

```bash
cd .worktrees/work-in-progress
git add .
git commit -m "save work in progress"
cd /path/to/repo
git wt -d work-in-progress
```

#### Option 2: Stash changes

```bash
cd .worktrees/work-in-progress
git stash push -m "WIP changes"
cd /path/to/repo
git wt -d work-in-progress

# Later, restore stash
git stash pop
```

#### Option 3: Force removal

```bash
git wt -D work-in-progress
```

### Warning

### Issue: Configuration Not Recognized

### Symptom

```
# Configuration set but not applied
git config wt.basedir
# → .worktrees

# But worktrees created in current directory
```

### Cause

### Diagnosis

```bash
# Check configuration origin
git config --show-origin wt.basedir

# Check all wt.* configurations
git config --list | grep ^wt\.

# Verify syntax
cat .git/config
```

### Solutions

### Fix scope

```bash
# Remove global config
git config --global --unset wt.basedir

# Set local config
git config --local wt.basedir ".worktrees"
```

### Fix syntax

```ini
# Incorrect
[wt]
    basedir = .worktrees  # Missing quotes

# Correct
[wt]
    basedir = ".worktrees"
```

### Validate configuration

```bash
# Use diagnostic script
scripts/check-worktree-config.sh
```

### Issue: Shell Integration Not Working

### Symptom

```bash
# Command not found
git wt
# → bash: git-wt: command not found

# Or switch doesn't change directory
gwts
# → (no directory change)
```

### Cause

### Diagnosis

```bash
# Check if git-wt is installed
which git-wt

# Check if shell functions are loaded
type gwt
type gwts
```

### Solutions

### For git-wt command

```bash
# Check installation
mise list | grep git-wt

# Reinstall if needed
mise install go:github.com/k1LoW/git-wt@latest

# Verify PATH
echo $PATH | grep -o '[^:]*mise[^:]*'
```

### For Zsh functions

```bash
# Check if functions are loaded
grep -r "gwt" ~/.zshrc ~/.config/zsh/

# Source configuration manually
source ~/.config/zsh/config/tools/git.zsh

# Verify functions
type gwts
```

### Reload shell

```bash
exec zsh
```

### Issue: File Copying Not Working

### Symptom

```bash
git wt feature/test --copy .env
# → .env file not copied to worktree
```

### Cause

### Diagnosis

```bash
# Check if source file exists
ls -la .env

# Check current directory
pwd

# Verify git-wt version
git wt --version
```

### Solutions

### Fix file path

```bash
# Use absolute path
git wt feature/test --copy /path/to/repo/.env

# Or use relative path from main repo
cd /path/to/repo
git wt feature/test --copy .env
```

### Use configuration

```bash
# Set permanent copy files
git config --add wt.copy ".env"
git config --add wt.copy ".env.local"

# Create worktree (files copied automatically)
git wt feature/test
```

### Manual copy as fallback

```bash
# Create worktree
git wt feature/test

# Copy files manually
cp .env .worktrees/test/.env
```

### Issue: Hooks Not Executing

### Symptom

```bash
git config --get-all wt.hook
# expected setup command is missing
```

### Cause

### Diagnosis

```bash
git config --get-all wt.hook
git config --get-all wt.deletehook
```

### Solutions

### Add the hook command

```bash
git config --add wt.hook "npm install"
```

### Verify hook execution

```bash
git config --add wt.hook "printf hook-ran > .git-wt-hook-check"
git wt test
rg -n "hook-ran" .git-wt-hook-check
```

### Issue: Worktree Path Conflicts

### Symptom

```
fatal: '/path/to/repo/.worktrees/feature' already exists
```

### Cause

### Solutions

#### Option 1: Remove existing directory

```bash
# Check if directory is a worktree
git wt | grep feature

# If not a worktree, safe to remove
rm -rf .worktrees/feature

# Create worktree
git wt feature/new-feature
```

#### Option 2: Use a different worktree name

```bash
# Keep the branch name but choose a different worktree directory name
git wt -b feature/new-feature feature-v2
```

#### Option 3: Use a different base directory

```bash
git wt -b feature/new-feature feature-v2 --basedir .worktrees
```

### Warning

## Performance Issues

### Issue: Slow Worktree Creation

### Symptom

### Causes

- Large repository
- Slow disk I/O
- `wt.hook` running heavy operations

### Diagnosis

```bash
# Time the operation
time git wt test

# Check configured hooks
git config --get-all wt.hook
```

### Solutions

### Optimize hooks

```bash
# Make hooks faster
# - Run npm install in background
# - Skip unnecessary operations
# - Cache dependencies

git config --unset-all wt.hook
git config --add wt.hook "npm install --prefer-offline"
```

### Use `--nocd`

```bash
# Skip checkout for faster creation
git wt feature/test --nocd

# Checkout later
cd .worktrees/test
git checkout feature/test
```

### Issue: Excessive Disk Usage

### Symptom

### Cause

### Solutions

### Share node_modules

```bash
# Create shared node_modules
mkdir -p .cache/node_modules
cd .cache
npm install

# Symlink in each worktree
cd /path/to/repo/.worktrees/feature-a
rm -rf node_modules
ln -s ../../.cache/node_modules node_modules
```

### Clean up build artifacts

```bash
git config --add wt.deletehook "rm -rf dist .next build"
```

### Use workspace feature

```bash
# package.json (root)
{
  "workspaces": [
    ".worktrees/*"
  ]
}
```

## Git Internal Issues

### Issue: Corrupted Worktree Metadata

### Symptom

```
fatal: not a git repository: '/path/to/repo/.git/worktrees/broken'
```

### Cause

### Solution

```bash
# Repair worktree
git worktree repair .worktrees/broken

# If repair fails, manual cleanup
rm -rf .git/worktrees/broken
rm -rf .worktrees/broken

# Recreate if needed
git wt existing-branch
```

### Issue: Detached HEAD in Worktree

### Symptom

### Diagnosis

```bash
cd .worktrees/feature-a
git status
# → HEAD detached at abc123
```

### Solution

```bash
# Checkout branch
git checkout feature/feature-a

# Or create new branch from current state
git checkout -b feature/feature-a-recovered
```

### Issue: Upstream Tracking Lost

### Symptom

### Solution

```bash
cd .worktrees/feature-a

# Set upstream
git branch --set-upstream-to=origin/feature/feature-a

# Or push with -u
git push -u origin feature/feature-a
```

### Prevention

```bash
git config worktree.guessRemote true
```

## Diagnostic Tools

### Check Configuration

```bash
# Run diagnostic script
scripts/check-worktree-config.sh

# Manual checks
git config --list | grep ^wt\.
git config --show-origin wt.basedir
```

### List All Worktrees

```bash
# Simple list
git wt

# Detailed list
git worktree list -v

# Show hidden details
cat .git/worktrees/*/gitdir
```

### Verify Worktree Integrity

```bash
# Check all worktrees
for wt in .git/worktrees/*; do
  name=$(basename "$wt")
  echo "Checking $name..."

  # Check if directory exists
  gitdir=$(cat "$wt/gitdir")
  if [ ! -d "$gitdir" ]; then
    echo "  ERROR: Directory not found"
  else
    echo "  OK"
  fi
done
```

### Clean Up Stale Worktrees

```bash
# Prune stale metadata
git worktree prune -v

# Remove orphaned directories
find .worktrees -maxdepth 1 -type d | while read dir; do
  name=$(basename "$dir")
  if ! git wt | grep -q "$name"; then
    echo "Orphaned directory: $dir"
    # rm -rf "$dir"  # Uncomment to remove
  fi
done
```

## Prevention Best Practices

### Always Use git wt Commands

```bash
# ✅ Correct
git wt feature/test
git wt -d feature/test

# ❌ Incorrect
mkdir .worktrees/test
rm -rf .worktrees/test
```

### Regular Maintenance

```bash
# Weekly cleanup script
#!/bin/bash
# cleanup-worktrees.sh

echo "Pruning stale worktrees..."
git worktree prune -v

echo "Listing remaining worktrees..."
git wt

echo "Cleanup completed"
```

### Use Version Control for Configuration

```bash
# Commit git configuration
git add .git/config
# Note: .git/config is not normally tracked, use separate config file

# Or document in README
cat > docs/worktree-setup.md <<EOF
# Worktree Setup

## Configuration

\`\`\`bash
git config wt.basedir ".worktrees"
git config worktree.guessRemote true
\`\`\`
EOF
```

### Team Guidelines

### Document worktree conventions

1. Always use `.worktrees/` as base directory
2. Use `git wt` commands only
3. Clean up worktrees after PR merge
4. Run `git worktree prune` regularly
5. Don't manually edit `.git/worktrees/`

## See Also

- [Command Reference](git-wt-commands.md)
- [Configuration Options](configuration.md)
- [Workflow Patterns](workflows.md)

## Emergency Recovery

### Nuclear Option: Reset Everything

### Warning

This recovery path removes worktrees forcefully. Back up the list, inspect each target path, and get explicit user approval before running the removal loop.

```bash
# Backup first
git worktree list > /tmp/worktrees-backup.txt

# Remove all worktrees
git worktree list | grep -v '(bare)' | awk '{print $1}' | while read wt; do
  git worktree remove --force "$wt"
done

# Prune metadata
git worktree prune

# Clean up directories
rm -rf .worktrees/*

# Verify
git worktree list
```

---

### Version

### Last Updated
