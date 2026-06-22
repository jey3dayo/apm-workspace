# git-wt quick reference

This file is only a task-to-PR shortcut. The source of truth for `git wt` behavior is the [git-worktree skill](../../git-worktree/SKILL.md).

## Basic Commands

- List worktrees: `git wt`
- Switch to an existing worktree or create a new one: `git wt <branch-or-worktree>`
- Create from a start point: `git wt <branch-or-worktree> <start-point>`
- Create with a different branch name: `git wt -b <branch> <worktree>`
- Safe-delete a worktree and branch: `git wt -d <branch-or-worktree>`
- Force-delete a worktree and branch: `git wt -D <branch-or-worktree>`

## Learn More

- [git-worktree skill](../../git-worktree/SKILL.md)
- [Command Reference](../../git-worktree/references/git-wt-commands.md)
- [Workflows](../../git-worktree/references/workflows.md)
- [Troubleshooting](../../git-worktree/references/troubleshooting.md)
