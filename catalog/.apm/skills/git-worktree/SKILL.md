---
name: git-worktree
description: Use when managing Git worktrees with `git wt` or `git worktree`, especially for branch isolation, `.worktrees/` layout, parallel work, cleaning up a worktree after its PR merges, or diagnosing worktree create/remove errors.
---

# Git Worktree Management

## Overview

Use `git wt` for normal list, switch/create, rename, and delete flows. Create worktrees only with `git wt`; `git worktree add` is denied (including `--detach` scratch checkouts). Drop to native `git worktree` only for low-level cleanup, diagnosis, or recovery.

This skill owns command syntax, troubleshooting, and the rule that work branches live in worktrees (First Pass). PR 作成から統合までの一連フローと、branch・worktree の削除判断（`git-branch-cleanup`）は対象外。

## First Pass

1. `git wt` で既存 worktree と使用中ブランチを確認する
2. 必要なら `git config --local wt.basedir ".worktrees"` を確認する
3. 作業ブランチは worktree で切り、メイン checkout を切り替えない（repo の AGENTS.md が default branch への直接 commit を定めていれば、メイン checkout の default branch 上で作業してよい）。編集対象が互いに素な Worker が同じ作業用 worktree を共有するのはよい
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

### Distribute Env Files After Creation

`wt.copy` が効くのは `git wt` での新規作成時のみ。native `git worktree add`、エージェントの worktree isolation、既存 worktree への遡及配布では、作成後に同梱スクリプトで main checkout から env ファイル（`.env` / `.env.local` / `.env.keys`、ネスト含む）を配る。

```bash
scripts/copy-env-files.sh <worktree-path>
scripts/copy-env-files.sh <worktree-path> <source-checkout-path>
```

### After the PR Merges

worktree を default branch へ切り替えて使い続けない。default branch の更新はメイン checkout で行う。

```bash
git -C <main-checkout> branch --show-current
git -C <main-checkout> rev-parse --abbrev-ref @{upstream}
git -C <main-checkout> pull --ff-only
```

1行目が default branch で、2行目がその remote の default branch（`origin/main` など）でなければ pull しない。メイン checkout を切り替えた持ち主を確かめ、戻してよいかをユーザーに聞く。worktree と branch の削除は `git-branch-cleanup` に従う。

### Diagnose

```bash
git wt --json
git worktree list
./scripts/check-worktree-config.sh
```

## Rules Of Thumb

- `wt.basedir` は repo-local にそろえる
- 同じ branch を複数 worktree で同時 checkout しない
- default branch（`main` / `develop` など）はメイン checkout だけが持つ。メイン checkout を作業ブランチへ切り替えず、worktree では default branch を checkout しない。別の worktree が default branch を握ると、メイン checkout が `fatal: 'main' is already used by worktree` で戻れなくなる
- 手動でディレクトリを消した後は `git worktree prune` を忘れない
- `.env` などローカルファイル配布が必要な時だけ `wt.copy` / `--copy` を使う
- dotenvx 管理のリポジトリでは `.env.keys` が gitignore されているため、`wt.copy` に `.env.keys` を含めないと新 worktree で復号が失敗する（グローバル設定例: `git config --global --add wt.copy ".env.keys"`）
- 並行作業で編集対象が重なりうる、または不明なときは、main repository を作業場所にしない

## Common Mistakes

- 既に別 worktree で使っている branch 名で新規作成しようとして詰まる
- worktree ディレクトリだけ消して metadata を残す
- `git wt <worktree>` と `git wt -b <branch> <worktree>` の意味を混同する
- repo ごとの `.worktrees/` 前提を global config だけで済ませる
- `wt.copy` 未設定のまま worktree を切り、`.env.keys` / `.env.local` が無くて dotenvx 復号や env 読み込みが失敗する

## References

- `references/git-wt-commands.md` — `git wt` の正確なフラグ・全コマンドが必要な時に読む
- `references/configuration.md` — `wt.basedir` / `wt.copy` など repo 設定の詳細が必要な時に読む
- `references/workflows.md` — feature 開発・並列作業などの手順パターンが必要な時に読む
- `references/troubleshooting.md` — エラー診断・復旧手順が必要な時に読む
