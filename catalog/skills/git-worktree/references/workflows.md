# Git Worktree Workflow Patterns

Practical workflow patterns for Git worktree usage in various development scenarios.

## Core Workflows

### Feature Branch Development

Standard workflow for feature development with worktrees.

### Setup

```bash
# Main repository stays on default branch (main)
cd /path/to/repo
git status  # Should be clean

# Create worktree for new feature
git wt feature/user-authentication
cd .worktrees/user-authentication
```

### Development

```bash
# Work on feature
vim src/auth.ts
git add src/auth.ts
git commit -m "feat: add user authentication"

# Continue development
vim tests/auth.test.ts
git add tests/auth.test.ts
git commit -m "test: add authentication tests"
```

### Cleanup

```bash
# After PR is merged
cd /path/to/repo
git wt -d feature/user-authentication
git branch -d feature/user-authentication
```

### Parallel Feature Development

Working on multiple features simultaneously.

### Scenario

```bash
# Feature A: Primary work
git wt feature/api-endpoints
cd .worktrees/api-endpoints
# ... work on Feature A ...

# Feature B: Secondary work (while Feature A's tests run)
cd /path/to/repo
git wt feature/ui-components
cd .worktrees/ui-components
# ... work on Feature B ...

# Switch between features easily
cd /path/to/repo
git wt feature/api-endpoints
# or
gwts  # Interactive selection (with Zsh integration)
```

### Benefits

- No stashing required
- Each feature has its own `node_modules` (if needed)
- Independent test/build processes

### Hotfix Workflow

Quickly fix production issues without affecting current work.

### Scenario

```bash
# Current work (in progress, uncommitted changes)
cd .worktrees/feature-in-progress
git status  # Shows uncommitted changes

# Create hotfix worktree from production branch
cd /path/to/repo
git wt hotfix/critical-bug origin/production

# Work on hotfix
cd .worktrees/critical-bug
vim src/buggy-code.ts
git add .
git commit -m "fix: resolve critical production bug"
git push origin hotfix/critical-bug

# Create PR, get it merged

# Clean up
cd /path/to/repo
git wt -d hotfix/critical-bug

# Resume original work (no stash/unstash needed)
cd .worktrees/feature-in-progress
# Continue working...
```

### PR Review Workflow

Review and test PRs without affecting your current work.

```bash
# Fetch PR branch
git fetch origin pull/123/head:pr-123

# Create worktree for PR review
git wt pr-123

# Test PR
cd .worktrees/pr-123
npm install
npm test
npm run build

# Leave review comments, then clean up
cd /path/to/repo
git wt -d pr-123
git branch -d pr-123
```

## Advanced Workflows

### AI Agent Parallel Execution

Multiple AI agents working on different tasks in parallel.

### Architecture

```
Main Repo (coordinator)
├── .worktrees/agent-1-task-a/  # Agent 1: Feature A
├── .worktrees/agent-2-task-b/  # Agent 2: Feature B
└── .worktrees/agent-3-task-c/  # Agent 3: Feature C
```

### Setup Script

```bash
#!/bin/bash
# setup-agent-worktrees.sh

TASKS=("task-a" "task-b" "task-c")

for i in "${!TASKS[@]}"; do
  TASK="${TASKS[$i]}"
  AGENT_ID=$((i + 1))

  # Create worktree for each agent
  git wt "agent-${AGENT_ID}-${TASK}"

  # Copy necessary files
  cp .env ".worktrees/${TASK}/.env"

  echo "Worktree for Agent ${AGENT_ID} (${TASK}) created"
done
```

### Agent Execution

```bash
# Agent 1
cd .worktrees/agent-1-task-a
# ... AI agent works here ...

# Agent 2 (parallel)
cd .worktrees/agent-2-task-b
# ... AI agent works here ...

# Agent 3 (parallel)
cd .worktrees/agent-3-task-c
# ... AI agent works here ...
```

### Cleanup

```bash
#!/bin/bash
# cleanup-agent-worktrees.sh

TASKS=("task-a" "task-b" "task-c")

for i in "${!TASKS[@]}"; do
  TASK="${TASKS[$i]}"
  AGENT_ID=$((i + 1))

  # Remove worktree
  git wt -d "agent-${AGENT_ID}-${TASK}"

  # Delete branch (if merged)
  git branch -d "agent-${AGENT_ID}-${TASK}"
done
```

### Continuous Integration (CI) Workflow

Use worktrees for parallel CI builds.

### Scenario

```bash
#!/bin/bash
# ci-parallel-test.sh

BRANCHES=("main" "develop" "feature/new-api")

for branch in "${BRANCHES[@]}"; do
  # Create worktree for each branch
  git wt -b "$branch" "${branch//\//-}" --basedir ci-builds

  # Run tests in background
  (
    cd "ci-builds/${branch//\//-}"
    npm install
    npm test
    npm run build
  ) &
done

# Wait for all tests to complete
wait

echo "All CI tests completed"
```

### Benefits

- Parallel execution (faster CI)
- Isolated dependencies
- No branch switching overhead

### Release Branch Maintenance

Maintain multiple release branches simultaneously.

### Scenario

```bash
# Create worktrees for each release branch
git wt -b release/v1.x v1 --basedir releases
git wt -b release/v2.x v2 --basedir releases
git wt -b release/v3.x v3 --basedir releases

# Backport fix to all versions
cd releases/v1
git cherry-pick abc123
git push origin release/v1.x

cd ../v2
git cherry-pick abc123
git push origin release/v2.x

cd ../v3
git cherry-pick abc123
git push origin release/v3.x
```

### Bisect with Worktrees

Use worktrees for git bisect without interrupting current work.

```bash
# Create worktree for bisect
git worktree add --detach .worktrees/bisect-session HEAD

cd .worktrees/bisect-session

# Start bisect
git bisect start
git bisect bad HEAD
git bisect good v1.0.0

# Test each commit
while [ $? -ne 0 ]; do
  npm test
  if [ $? -eq 0 ]; then
    git bisect good
  else
    git bisect bad
  fi
done

# Found bad commit
git bisect log

# Clean up
cd /path/to/repo
git wt -d bisect-session
```

## Hooks

`git-wt` 0.29.0 uses Git config entries for hooks.

### Post-Create Hook: Dependency Installation

Run setup commands after creating a new worktree. Hooks run in the new worktree directory.

```bash
git config --add wt.hook "npm install"
git config --add wt.hook "go generate ./..."
```

Hooks do not run when switching to an existing worktree.

### Copy Local Files

Use `wt.copy` for local files that should follow new worktrees.

```bash
git config --add wt.copy ".env.local"
git config --add wt.copy ".vscode/"
```

For broader copying, enable ignored, untracked, or modified file copying intentionally.

```bash
git config wt.copyignored true
git config wt.copyuntracked true
git config wt.copymodified true
```

### Pre-Delete Hook

Run cleanup or safety checks before deleting a worktree.

```bash
git config --add wt.deletehook "git status --short"
```

## Team Collaboration

### Shared Worktree Convention

Establish team conventions for worktree usage.

### Team Guidelines

1. Base Directory: Always use `.worktrees/`
2. Naming Convention: `{type}/{description}` (e.g., `feature/user-auth`)
3. Main Branch Protection: Never work directly in main repository
4. Cleanup: Remove worktrees after PR merge

### Shared Configuration

```gitattributes
# .gitattributes
.worktrees/** linguist-vendored
```

### Shared Configuration

```gitignore
# .gitignore
.worktrees/
```

### Shared Configuration

```toml
# mise.toml
[tasks.worktree-create]
run = "git wt $1"

[tasks.worktree-cleanup]
run = "git wt --json"
```

### Code Review with Worktrees

Efficient code review workflow for teams.

### Reviewer Workflow

```bash
# Reviewer fetches PR into a local branch without switching the main checkout
git fetch origin pull/456/head:pr-456-review

# Create worktree for review
git wt pr-456-review

cd .worktrees/pr-456-review

# Run tests
npm test

# Test manually
npm run dev

# Leave review
gh pr review 456 --comment -b "LGTM! Tests pass."

# Clean up
cd /path/to/repo
git wt -d pr-456-review
```

### Author Workflow

```bash
# Create worktree for PR fixes
git wt pr-456-fixes

cd .worktrees/pr-456-fixes

# Address comments
vim src/file.ts
git add .
git commit -m "fix: address review comments"
git push origin pr-456-fixes

# Clean up after merge
cd /path/to/repo
git wt -d pr-456-fixes
```

## Performance Optimization

### Shared Object Database

Worktrees share the same `.git` object database, saving disk space.

### Disk Usage Comparison

```bash
# Without worktrees (3 clones)
3 × (repo size) = 3 × 1GB = 3GB

# With worktrees (1 repo + 2 worktrees)
1 × (repo size) + 2 × (working directory) = 1GB + 2 × 100MB = 1.2GB
```

### Savings

### Parallel Operations

Leverage worktrees for parallel operations.

### Example: Parallel Testing

```bash
#!/bin/bash
# parallel-test.sh

BRANCHES=("main" "develop" "feature/new-feature")

for branch in "${BRANCHES[@]}"; do
  (
    git wt -b "$branch" "test-${branch//\//-}"
    cd "test-${branch//\//-}"
    npm test
    cd ..
    git wt -d "test-${branch//\//-}"
  ) &
done

wait
echo "All tests completed"
```

### Build Caching

Share build caches between worktrees.

### Configuration

```bash
# Shared cache directory
BUILD_CACHE_DIR=/path/to/repo/.cache/build
NODE_MODULES_CACHE=/path/to/repo/.cache/node_modules
```

### Hook Integration

```bash
git config --add wt.symlink ".cache/"
```

## Troubleshooting Workflows

### Stale Worktree Recovery

Recover from accidentally deleted worktree directories.

```bash
# List all worktrees (including stale)
git worktree list

# Prune stale worktrees
git worktree prune -v

# Recreate if needed
git wt existing-branch
```

### Locked Worktree Resolution

Resolve locked worktree issues.

```bash
# Check if worktree is locked
git worktree list

# Unlock worktree
git worktree unlock .worktrees/locked-worktree

# Remove worktree
git wt -d locked-worktree
```

## See Also

- [Command Reference](git-wt-commands.md)
- [Configuration Options](configuration.md)
- [Troubleshooting](troubleshooting.md)

---

### Version

### Last Updated
