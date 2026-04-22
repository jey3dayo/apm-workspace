---
name: codex-code-review
description: >-
  Review code changes using Codex. Use when user asks to review code,
  check code quality, or wants feedback before committing or creating
  a pull request.
  Triggers: "コードレビュー", "code review with codex", "codex でレビュー",
  "変更をチェック", "review my changes", "review code".
allowed-tools: Bash(codex:*), Bash(jq:*), Bash(git:*), Read, Edit, Grep, Glob
---

# Codex Code Review

Review code changes with Codex and apply fixes if issues are found.

## Workflow

### 1. Detect Changes and Determine Mode

```bash
git status --porcelain
```

- Output present → uncommitted changes mode
- No output → branch diff mode (diff against default branch)

### 2. Run Review

> **Resume-first**: 先行する Codex セッション（codex-system での設計相談等）があれば
> `resume --last` でコンテキストを引き継ぐ。セッションがなければ新規実行にフォールバック。
>
> **Resume 制約**: resume 時は `--sandbox` 指定不可（セッション元から継承）。`--full-auto`, `--all` 等は指定可能。プロンプトは stdin 経由で渡す。
>
> **When to skip resume**: このレビュー対象と同じ CWD / 同じ作業について Codex セッションを開始していない場合は、
> `resume --last` を使わず fresh read-only exec から始める。
>
> **Error handling**: codex が非ゼロで終了した場合（resume / fresh exec 両方失敗）、
> エラーを報告し、手動レビューにフォールバックする。

#### Uncommitted Changes Mode

```bash
UNSTAGED_DIFF=$(git diff)
STAGED_DIFF=$(git diff --cached)
REVIEW_PROMPT="
Review the following uncommitted changes. Identify:
1. Bugs or logic errors
2. Security concerns
3. Type safety issues
4. Code style or readability problems
5. Missing error handling

Be specific and concise. Reference file paths and line numbers.
Output JSON: {\"issues\": [{\"file\": \"...\", \"line\": N, \"severity\": \"critical|warning|info\", \"message\": \"...\"}], \"summary\": \"...\"}

---
## Unstaged changes
${UNSTAGED_DIFF}

## Staged changes
${STAGED_DIFF}
"

RAW_OUTPUT=$(echo "$REVIEW_PROMPT" | codex exec resume --last 2>/dev/null)
RESUME_STATUS=$?

# resume --last can pick up stale context. If output is empty or clearly unrelated,
# retry once with a fresh read-only exec before evaluating the result.
if [ $RESUME_STATUS -ne 0 ] || [ -z "$RAW_OUTPUT" ]; then
  RAW_OUTPUT=$(codex exec --sandbox read-only "$REVIEW_PROMPT" 2>/dev/null)
fi

echo "$RAW_OUTPUT"
```

#### Branch Diff Mode

```bash
BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$BASE" ]; then
  if git rev-parse --verify main >/dev/null 2>&1; then
    BASE=main
  elif git rev-parse --verify master >/dev/null 2>&1; then
    BASE=master
  else
    echo "Could not determine base branch" >&2
    exit 1
  fi
fi

REVIEW_PROMPT="
Review the following branch changes against ${BASE}. Identify:
1. Bugs or logic errors
2. Security concerns
3. Type safety issues
4. Code style or readability problems
5. Missing error handling

Be specific and concise. Reference file paths and line numbers.
Output JSON: {\"issues\": [{\"file\": \"...\", \"line\": N, \"severity\": \"critical|warning|info\", \"message\": \"...\"}], \"summary\": \"...\"}

---
$(git diff ${BASE}...HEAD)
"

RAW_OUTPUT=$(echo "$REVIEW_PROMPT" | codex exec resume --last 2>/dev/null)
RESUME_STATUS=$?

if [ $RESUME_STATUS -ne 0 ] || [ -z "$RAW_OUTPUT" ]; then
  RAW_OUTPUT=$(codex exec --sandbox read-only "$REVIEW_PROMPT" 2>/dev/null)
fi

echo "$RAW_OUTPUT"
```

### 3. Extract Results

```bash
RAW_OUTPUT='<codex output>'

if ! echo "$RAW_OUTPUT" | jq -e '.issues and .summary' >/dev/null 2>&1; then
  echo "Codex output was not valid JSON; switch to manual review." >&2
  echo "$RAW_OUTPUT"
  exit 1
fi

echo "$RAW_OUTPUT" | jq '.issues'
```

### 4. Evaluate and Respond

- `resume --last` was skipped, failed, or returned empty output → rerun once with a fresh read-only exec
- JSON parse failed / output clearly unrelated to current diff → report the raw output and fall back to manual review
- Critical issues found → Read the affected file and apply fixes with Edit
- Warnings only → Share with user and confirm whether to fix
- Info only / no issues → Report review complete

### 5. Re-review After Fixes

If fixes were applied, return to step 1 and re-run the review.
Repeat until zero issues remain (max 3 iterations).
If unresolved after 3 attempts, report remaining issues and defer to the user.
