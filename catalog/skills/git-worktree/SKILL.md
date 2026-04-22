---
name: git-worktree
description: Use when managing Git worktrees with `git wt` or `git worktree`, especially for branch isolation, `.worktrees/` layout, parallel work, or diagnosing worktree create/remove errors.
---

# Git Worktree Management

## Overview

Use `git wt` for normal create, switch, and remove flows. Drop to native `git worktree` only when you need low-level cleanup or diagnosis.

Read the reference files only when you need exact flags, repo-specific configuration details, or troubleshooting steps.

## When to Use

- 複数ブランチを別ディレクトリで同時に触りたい
- `git wt create` や `git worktree add` の使い分けを確認したい
- `.worktrees/` 運用にそろえたい
- AI agent や並列作業用に checkout を分離したい
- `fatal: invalid reference` など worktree まわりのエラーを調べたい

使わない場面:

- PR 作成から統合までの一連フローを進めたい
- 追加ディレクトリ不要の通常ブランチ運用だけで足りる

## First Pass

1. `git wt list` で既存 worktree と使用中ブランチを確認する
2. 必要なら `git config --local wt.basedir ".worktrees"` を確認する
3. メイン checkout を保護し、実作業は worktree 側で行う前提にする
4. 今回の目的が「新規 branch」「既存 branch」「掃除/診断」のどれか決める

## Common Operations

### Create

```bash
git wt create feature/my-task
git wt create -b existing-branch
git wt create feature/my-task --path .worktrees/my-task
```

### Switch

```bash
git wt switch feature/my-task
git wt switch .worktrees/my-task
```

### Remove and Clean Up

```bash
git wt remove feature/my-task
git wt remove -f feature/my-task
git worktree prune
```

### Diagnose

```bash
git wt list --verbose
git worktree list
./scripts/check-worktree-config.sh
```

## Rules Of Thumb

- `wt.basedir` は repo-local にそろえる
- 同じ branch を複数 worktree で同時 checkout しない
- 手動でディレクトリを消した後は `git worktree prune` を忘れない
- `.env` などローカルファイル配布が必要な時だけ `wt.copyFiles` を使う
- main repository を日常作業場所にしない

## Common Mistakes

- 既に別 worktree で使っている branch 名で新規作成しようとして詰まる
- worktree ディレクトリだけ消して metadata を残す
- `git wt create` と `git wt create -b` の意味を混同する
- repo ごとの `.worktrees/` 前提を global config だけで済ませる

## References

- `references/git-wt-commands.md`
- `references/configuration.md`
- `references/workflows.md`
- `references/troubleshooting.md`
