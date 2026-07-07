---
name: git-worktree
description: Use when managing Git worktrees with `git wt` or `git worktree`, especially for branch isolation, `.worktrees/` layout, parallel work, or diagnosing worktree create/remove errors.
---

# Git Worktree Management

## Overview

Use `git wt` for normal list, switch/create, rename, and delete flows. Drop to native `git worktree` only when you need low-level cleanup or diagnosis.

This skill owns command syntax and troubleshooting. It does not decide whether a new isolated workspace should be created for feature work; use `using-git-worktrees` for that workflow decision. PR 作成から統合までの一連フローや、追加ディレクトリ不要の通常ブランチ運用はこのスキルの対象外。

## First Pass

1. `git wt` で既存 worktree と使用中ブランチを確認する
2. 必要なら `git config --local wt.basedir ".worktrees"` を確認する
3. メイン checkout を保護し、実作業は worktree 側で行う前提にする
4. 今回の目的が「新規 branch」「既存 branch」「掃除/診断」のどれか決める

## Common Operations

### List

```bash
git wt
git wt --json
```

### Switch or Create

`git wt <name>` switches to an existing worktree when it exists, otherwise creates a worktree and branch.

```bash
git wt feature/my-task
git wt feature/my-task origin/main
git wt -b feature/my-task my-task
```

### Rename

```bash
git wt -m old-name new-name
git wt -M old-name new-name
```

### Delete and Clean Up

```bash
git wt -d feature/my-task
git wt -D feature/my-task
git worktree prune -v
```

### Diagnose

```bash
git wt --json
git worktree list
./scripts/check-worktree-config.sh
```

## Rules Of Thumb

- `wt.basedir` は repo-local にそろえる
- 同じ branch を複数 worktree で同時 checkout しない
- 手動でディレクトリを消した後は `git worktree prune` を忘れない
- `.env` などローカルファイル配布が必要な時だけ `wt.copy` / `--copy` を使う
- main repository を日常作業場所にしない

## Common Mistakes

- 既に別 worktree で使っている branch 名で新規作成しようとして詰まる
- worktree ディレクトリだけ消して metadata を残す
- `git wt <worktree>` と `git wt -b <branch> <worktree>` の意味を混同する
- repo ごとの `.worktrees/` 前提を global config だけで済ませる

## References

- `references/git-wt-commands.md` — `git wt` の正確なフラグ・全コマンドが必要な時に読む
- `references/configuration.md` — `wt.basedir` / `wt.copy` など repo 設定の詳細が必要な時に読む
- `references/workflows.md` — feature 開発・並列作業などの手順パターンが必要な時に読む
- `references/troubleshooting.md` — エラー診断・復旧手順が必要な時に読む
