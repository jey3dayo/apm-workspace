---
name: codex-plan-review
description: >-
  Review implementation plan files with Codex to identify potential risks,
  missing steps, and technical concerns. Use when you want a quality check
  before starting implementation.
  Triggers: "プランをレビュー", "plan review", "実装前にチェック",
  "codex でレビュー", "プランの確認", "review the plan".
allowed-tools: Bash(codex:*), Bash(ls:*), Bash(sed:*), Read
---

# Codex Plan Review

Review the latest plan file in `~/.claude/plans/` with Codex and report any issues.

## Workflow

### 1. Identify the Latest Plan File

```bash
LATEST_PLAN=$(ls -t ~/.claude/plans/*.md 2>/dev/null | sed -n '1p')

if [ -z "$LATEST_PLAN" ]; then
  echo "No plan files found in ~/.claude/plans" >&2
  exit 1
fi

echo "$LATEST_PLAN"
```

### 2. Read the Plan Content

Read the entire plan file using the Read tool.

### 3. Run Review with Codex

> **Resume-first**: 先行する Codex セッション（codex-system での設計相談等）があれば
> `resume --last` でコンテキストを引き継ぐ。セッションがなければ新規実行にフォールバック。
>
> **Resume 制約**: resume 時は `--sandbox` 指定不可（セッション元から継承）。`--full-auto`, `--all` 等は指定可能。プロンプトは stdin 経由で渡す。
>
> **When to skip resume**: 同じ CWD / 同じ plan について先行する Codex セッションがない場合は、
> `resume --last` を使わず fresh read-only exec を使う。
>
> **Error handling**: codex が非ゼロで終了した場合（resume / fresh exec 両方失敗）、
> エラーを報告し、手動レビューにフォールバックする。

```bash
REVIEW_PROMPT="
Review the following implementation plan. Identify:
1. Potential risks and failure points
2. Missing steps or edge cases
3. Technical concerns or anti-patterns
4. Scope creep or unnecessary complexity

Be specific and concise. If the plan looks solid, say so.

---
<plan content here>
"

RAW_OUTPUT=$(echo "$REVIEW_PROMPT" | codex exec resume --last 2>/dev/null)
RESUME_STATUS=$?

if [ $RESUME_STATUS -ne 0 ] || [ -z "$RAW_OUTPUT" ]; then
  RAW_OUTPUT=$(codex exec --sandbox read-only "$REVIEW_PROMPT" 2>/dev/null)
  FRESH_STATUS=$?
else
  FRESH_STATUS=0
fi

if [ $RESUME_STATUS -ne 0 ] && [ $FRESH_STATUS -ne 0 ]; then
  echo "Codex review failed; switch to manual review." >&2
  exit 1
fi

echo "$RAW_OUTPUT"
```

### 4. Report Results

- No plan files found → Report a `Critical` blocker and ask for a plan file or path before retrying
- Critical issues found → Report as `Critical` with specific findings and suggested fixes
- Minor concerns only → Report as `Minor`; implementation can proceed with notes
- No issues → Report as `Ready`; implementation can proceed
