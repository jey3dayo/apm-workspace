# Work-Log File Layout

Use these files under `tmp/work-log/` by default. Create only the files needed for the task, but prefer this naming when splitting an existing report.

When reorganizing an existing all-in-one report, migrate its content into the standard files and remove or replace the old duplicate file. Do not leave two files that both look like the primary report.

If a legacy file must remain because a user linked it or another workflow expects the path, replace its body with a short deprecation pointer to these canonical files. It must not contain fresher daily rows, business-day counts, leave adjustments, or raw evidence than the standard files.

## `report.md`

Purpose: final manager-facing report.

Rules:

- Keep it Slack-ready.
- Use one line per theme.
- Use `<theme>: <date range or date list> <N営業日>`.
- If `leave-days.md` exists and the submitted number must exclude leave, use `<theme>: <date range or date list> <N営業日>（有休等除外後 <M日>）`.
- If `leave-days.md` includes public holidays or company holidays, use an explicit label such as `<theme>: <date range or date list> <N営業日>（公休日・有休等除外後 <M日>）`.
- If overtime-included effort is optional, put the scheduled-working-hours submitted effort first and the overtime-included conversion second. Use `提出工数（所定労働時間）`, `工数換算（残業含む）`, and `残業時間`; do not use awkward labels such as `参考残業`.
- Do not include commit hashes, raw log excerpts, or long explanations.
- Include a short note only when it affects interpretation, such as "祝日は未除外".

Example:

```markdown
CA Connect Site 初期構築: 4/25-5/16 14営業日
CA Connect Site 本番・認証・リリース準備: 5/13-6/14 23営業日
CA Connect Site FAQ・通知・運用調整: 6/18-6/19 2営業日
```

Overtime-optional example:

```markdown
提出工数（所定労働時間）: 35.5日
工数換算（残業含む）: 47.47日

計算:
提出工数: 45.0営業日 - 公休日4.0日 - 有休等5.5日 = 35.5日
工数換算: 35.5日 + 残業換算11.97日 = 47.47日

内訳:

- 残業時間: 95.76時間（8時間=1日換算で11.97日）
```

## `work-history.md`

Purpose: source of truth for report rows.

Recommended columns:

```markdown
| テーマ | 期間 | 営業日数 | 主な内容 | 根拠 |
| ------ | ---- | -------: | -------- | ---- |
```

When `leave-days.md` exists, prefer adding an explicit leave-adjusted count:

```markdown
| テーマ | 期間 | 営業日数 | 除外日数 | 工数日付カウント | 主な内容 | 根拠 |
| ------ | ---- | -------: | -------: | ---------------: | -------- | ---- |
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

## `leave-days.md`

Purpose: source of truth for paid leave, half-day leave, public holidays, company holidays, holidays supplied by the user, or other date-count exclusions.

Recommended columns:

```markdown
| 日付 | 曜日 | 区分 | 除外日数 | 根拠 | 備考 |
| ---- | ---- | ---- | -------: | ---- | ---- |
```

Rules:

- Use this file whenever work is counted by dates and a user provides leave, public/company holiday, holiday calendar, calendar screenshot, or attendance evidence, including attendance screenshots, that should not be counted as work.
- Keep one row per excluded date. Use fractional values such as `0.5` for half-day leave.
- Use explicit `区分` values such as `有休`, `AM有休`, `PM有休`, `公休日`, or `会社休日`.
- Do not double-count holidays that fall on Saturdays or Sundays. Weekend holidays are already excluded by the Saturday/Sunday rule, so add them only as zero-day audit notes when needed.
- `work-history.md` should summarize the total excluded days, include the leave-adjusted work-day count when relevant, and point to `leave-days.md`; do not duplicate the full leave table there.
- `report.md` may mention the leave-adjusted total in one short note when that affects what should be submitted.
- Recalculate the total from this file before final reporting.

## `git-log-evidence.md`

Purpose: raw-ish support material.

Include:

- Commands or source names used, such as `git log --all --no-merges`, `CHANGELOG.md`, `TODO.md`, issues, or Slack notes.
- Representative commit excerpts where useful.
- Notes about incomplete evidence, failed fetches, missing holiday calendars, or assumptions.

Keep this file useful for recomputation, not polished for managers.

## Legacy all-in-one files

Purpose: compatibility pointer only.

Rules:

- Do not keep an all-in-one work-log such as `effort-report.md` as a parallel source of truth after `report.md`, `work-history.md`, `work-log.md`, `leave-days.md`, and `git-log-evidence.md` exist.
- If preserving the path is useful, replace the content with a short note that names the canonical files and says not to update the legacy file as the primary report.
- During final checks, compare the latest covered date in every legacy file with the standard files. The standard files must be at least as fresh.
