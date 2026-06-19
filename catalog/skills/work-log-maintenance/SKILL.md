---
name: work-log-maintenance
description: "Maintain work-log artifacts and produce manager-facing Slack reports with business-day counts. Use when asked to update work logs, summarize work periods, split work-log files, compute business days, or prepare short manager reports from evidence such as git log, changelog, TODOs, issues, Slack notes, or existing work-log files."
---

# Work Log Maintenance

Use this skill to turn evidence of work into a short manager-facing report. The primary output is a Slack-ready business-day summary; detailed logs and raw evidence support that report but should not crowd it.

## Output Priority

1. `report.md` - required when the user asks for a report. Keep it short enough to paste into Slack.
2. `work-history.md` - preferred source of truth for report rows: theme, date range(s), business-day count, and short summary.
3. `work-log.md` - daily detail: date, work window if known, commit count if relevant, and main work.
4. `git-log-evidence.md` - evidence excerpts from `git log`, `CHANGELOG.md`, `TODO.md`, issues, Slack notes, or manual notes.

Default location is `tmp/work-log/` unless the user specifies another path. Keep product code untouched unless the user explicitly asks for product changes. Treat `tmp/` work-log artifacts as local reporting artifacts and do not commit, push, or open a PR unless explicitly requested.

For the detailed file contract, read `references/report-layout.md` before creating or restructuring work-log files.

## Workflow

1. Inspect repository or workspace guidance first when present, then check the current worktree status.
2. Identify evidence sources. Prefer existing work-log files, `git log`, `CHANGELOG.md`, `TODO.md`, issues, and user-provided Slack examples. Git is strong evidence, but this skill must also work from manual notes or non-Git evidence.
3. If complete Git history matters, consider `git fetch --all --prune`. If it fails or network is unavailable, continue from local evidence and record the limitation in `git-log-evidence.md` or a short note.
4. Build or update `work-history.md` first when producing a manager report. Group work by theme, not by commit hash.
5. Update `work-log.md` only when daily detail is requested, already exists, or is needed to justify the period grouping.
6. Put raw excerpts and source notes in `git-log-evidence.md`; keep hashes and long evidence out of `report.md`.
7. Write `report.md` last from `work-history.md`, using the Slack format below.

## Slack Report Format

Use one line per theme:

```text
<theme>: <date range or date list> <N営業日>
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
- Exclude holidays only when the user provides a holiday calendar or a repository-local holiday source. Otherwise state or record that holidays were not excluded.
- For separated ranges or dates, count unique weekdays only once.
- Normalize continuous weekdays into a range and non-contiguous dates into comma-separated segments.
- When the same theme has overlapping ranges, merge the dates before calculating business days.
- When one day has multiple themes, split it only when the evidence clearly supports the split; otherwise keep it with the dominant theme and note the ambiguity in evidence.

## Update Rules

- Update existing dates, themes, and periods in place. Avoid duplicate rows.
- If a theme name changes but evidence points to the same work, rename the existing period instead of adding a near-duplicate.
- Keep `report.md` concise: no commit hashes, long bullet lists, raw logs, or methodology paragraphs.
- Keep uncertainty in support files, not in the Slack-ready message, unless the uncertainty changes what should be reported.

## Final Check

Before reporting completion:

- Recalculate every business-day count from the listed dates.
- Check for duplicated dates inside each theme.
- Check that `report.md` follows `<theme>: <date range or date list> <N営業日>`.
- Check that raw evidence lives in `git-log-evidence.md` or notes, not in `report.md`.
- State which files were updated and whether holiday exclusion was applied.
