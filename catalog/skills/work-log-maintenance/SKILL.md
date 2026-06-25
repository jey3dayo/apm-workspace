---
name: work-log-maintenance
description: "Maintain work-log artifacts and produce manager-facing Slack reports with business-day counts. Use when asked to update work logs, summarize work periods, split work-log files, compute business days, or prepare short manager reports from evidence such as git log, changelog, TODOs, issues, Slack notes, or existing work-log files."
---

# Work Log Maintenance

Use this skill to turn evidence of work into a short manager-facing report. The primary output is a Slack-ready business-day summary; detailed logs and raw evidence support that report but should not crowd it. Keep exactly one canonical reporting path: `report.md` -> `work-history.md` -> `work-log.md` -> `leave-days.md` -> `git-log-evidence.md`.

## Output Priority

1. `report.md` - required when the user asks for a report. Keep it short enough to paste into Slack.
2. `work-history.md` - preferred source of truth for report rows: theme, date range(s), business-day count, and short summary.
3. `work-log.md` - daily detail: date, work window if known, commit count if relevant, and main work.
4. `leave-days.md` - non-working day adjustments such as paid leave, half-day leave, public holidays, company holidays, or other user-provided exclusions from work-day counts.
5. `git-log-evidence.md` - evidence excerpts from `git log`, `CHANGELOG.md`, `TODO.md`, issues, Slack notes, or manual notes.

Default location is `tmp/work-log/` unless the user specifies another path. Keep product code untouched unless the user explicitly asks for product changes. Treat `tmp/` work-log artifacts as local reporting artifacts and do not commit, push, or open a PR unless explicitly requested.

For the detailed file contract, read `references/report-layout.md` before creating or restructuring work-log files.

Do not keep updating legacy all-in-one files such as `effort-report.md` after the standard files exist. If such a file exists, convert it into a short deprecated pointer to the standard files unless the user explicitly asks to preserve it as a standalone artifact.

## Workflow

1. Inspect repository or workspace guidance first when present, then check the current worktree status.
2. Identify evidence sources. Prefer existing work-log files, `git log`, `CHANGELOG.md`, `TODO.md`, issues, and user-provided Slack examples. Git is strong evidence, but this skill must also work from manual notes or non-Git evidence.
3. If complete Git history matters, consider `git fetch --all --prune`. If it fails or network is unavailable, continue from local evidence and record the limitation in `git-log-evidence.md` or a short note.
4. If legacy or duplicate work-log files exist, choose the standard files as the canonical targets before editing. Migrate useful content into the standard files, then replace the legacy file with a deprecated pointer instead of leaving it fresher than the standard files.
5. Build or update `work-history.md` first when producing a manager report. Group work by theme, not by commit hash.
6. Update `work-log.md` when daily detail exists, is requested, or is needed to justify the period grouping. Update existing dates in place and add missing recent dates, including explicit zero-work or no-commit days when they affect the requested period.
7. If the user provides paid leave, half-day leave, public holidays, company holidays, holiday calendars, or attendance screenshots, record the date adjustments in `leave-days.md` and reference that file from `work-history.md`. Do not bury leave or holiday exclusions only in prose.
8. Put raw excerpts and source notes in `git-log-evidence.md`; keep hashes and long evidence out of `report.md`.
9. Write `report.md` last from `work-history.md`, using the Slack format below.

## Slack Report Format

Use one line per theme:

```text
<theme>: <date range or date list> <N営業日>
```

When `leave-days.md` has exclusions and the user needs work counted by dates, append the leave-adjusted count in the same line:

```text
<theme>: <date range or date list> <N営業日>（有休等除外後 <M日>）
```

If `leave-days.md` includes public holidays or company holidays, name those exclusions explicitly:

```text
<theme>: <date range or date list> <N営業日>（公休日・有休等除外後 <M日>）
```

Examples:

```text
SERECA改修: 3/1-3/19 13営業日
Cygate: 3/21-4/12 17営業日
LoCA CDKインフラ修正: 4/15-4/16, 4/24 3営業日
SERECA 調整＆リリース: 4/15,16,22 3営業日
SERECA 仕様調整: 5/7-5/9 3営業日
```

Use compact month/day notation when the year is obvious from context. Include the year when ranges cross years or ambiguity is likely.

## Business-Day Rules

- Count date ranges inclusively.
- Exclude Saturdays and Sundays.
- Exclude public holidays or company holidays only when the user provides a holiday calendar, attendance/calendar screenshot, or a repository-local holiday source. Otherwise state or record that holidays were not excluded.
- Keep paid leave, half-day leave, public holidays, company holidays, and other user-provided exclusion days in `leave-days.md`. Use explicit `区分` values such as `有休`, `AM有休`, `PM有休`, `公休日`, or `会社休日`. When reporting actual work-day counts, subtract those exclusions from the business-day count and show both numbers when useful.
- Do not double-count holidays that fall on Saturdays or Sundays. Weekend holidays are already excluded by the Saturday/Sunday rule, so add them to `leave-days.md` only as a zero-day note when the distinction matters for auditability.
- Treat attendance screenshots as evidence for `leave-days.md` first, not as prose-only notes in `work-history.md` or `report.md`.
- For separated ranges or dates, count unique weekdays only once.
- Normalize continuous weekdays into a range and non-contiguous dates into comma-separated segments.
- When the same theme has overlapping ranges, merge the dates before calculating business days.
- When one day has multiple themes, split it only when the evidence clearly supports the split; otherwise keep it with the dominant theme and note the ambiguity in evidence.

## Update Rules

- Update existing dates, themes, and periods in place. Avoid duplicate rows.
- When splitting a legacy all-in-one report, replace it with the standard files instead of leaving a second source of truth behind. Keep a legacy file only when the user explicitly asks to preserve it.
- If a theme name changes but evidence points to the same work, rename the existing period instead of adding a near-duplicate.
- Keep `report.md` concise: no commit hashes, long bullet lists, raw logs, or methodology paragraphs.
- Keep uncertainty in support files, not in the Slack-ready message, unless the uncertainty changes what should be reported.
- After updating any work-log artifact, check whether newer data exists in a legacy or duplicate file. If it does, either migrate it into the standard files or mark the duplicate as deprecated before finishing.
- If `leave-days.md` exists, do not duplicate its leave table in `work-history.md`; add or update a leave-adjusted work-day count column or short summary there and link the file as the source of truth.

## Final Check

Before reporting completion:

- Recalculate every business-day count from the listed dates.
- Check for duplicated dates inside each theme.
- Check that `report.md` follows `<theme>: <date range or date list> <N営業日>`.
- Check that raw evidence lives in `git-log-evidence.md` or notes, not in `report.md`.
- Check that `leave-days.md`, `work-history.md`, `work-log.md`, `git-log-evidence.md`, and `report.md` agree on the latest covered date, business-day count, and leave-adjusted work-day count when leave data is present.
- Recalculate exclusion totals from `leave-days.md` by category, including paid leave and public/company holidays, and confirm `business days - excluded days = reported work-day count`.
- Check that no legacy all-in-one file, especially `effort-report.md`, is newer or more complete than the standard files. If one remains for compatibility, it must clearly point to the canonical files and say not to update it as the primary report.
- State which files were updated and whether holiday exclusion was applied.
