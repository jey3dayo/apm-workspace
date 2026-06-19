# Work-Log File Layout

Use these files under `tmp/work-log/` by default. Create only the files needed for the task, but prefer this naming when splitting an existing report.

## `report.md`

Purpose: final manager-facing report.

Rules:

- Keep it Slack-ready.
- Use one line per theme.
- Use `<theme>: <date range or date list> <N営業日>`.
- Do not include commit hashes, raw log excerpts, or long explanations.
- Include a short note only when it affects interpretation, such as "祝日は未除外".

Example:

```markdown
CA Connect Site 初期構築: 4/25-5/16 14営業日
CA Connect Site 本番・認証・リリース準備: 5/13-6/14 23営業日
CA Connect Site FAQ・通知・運用調整: 6/18-6/19 2営業日
```

## `work-history.md`

Purpose: source of truth for report rows.

Recommended columns:

```markdown
| テーマ | 期間 | 営業日数 | 主な内容 | 根拠 |
| ------ | ---- | -------: | -------- | ---- |
```

Rules:

- One row per reportable theme or project.
- Periods may contain multiple segments, such as `4/15-4/16, 4/24`.
- Keep the summary short but specific enough to justify the Slack line.
- Use this file to resolve naming, grouping, and period boundaries before writing `report.md`.

## `work-log.md`

Purpose: daily detail for auditing and later regrouping.

Recommended columns:

```markdown
| 日付 | 曜日 | 作業窓 | commit 数 | 主な作業 |
| ---- | ---- | ------ | --------: | -------- |
```

Rules:

- Use when daily detail already exists or when the period grouping needs support.
- Update existing dates in place.
- If there are no commits but there was manual work, record the evidence source instead of forcing commit counts.

## `git-log-evidence.md`

Purpose: raw-ish support material.

Include:

- Commands or source names used, such as `git log --all --no-merges`, `CHANGELOG.md`, `TODO.md`, issues, or Slack notes.
- Representative commit excerpts where useful.
- Notes about incomplete evidence, failed fetches, missing holiday calendars, or assumptions.

Keep this file useful for recomputation, not polished for managers.
