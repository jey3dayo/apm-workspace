---
name: mole-management
description: Manage Mole (`mo`) cleanup and disk-space triage on macOS, including safe `mo clean --dry-run` review, Mole whitelist updates, Homebrew cache cleanup, Playwright cache cleanup, and Docker Desktop pruning. Use when the user mentions Mole, `mo clean`, disk full notifications, cleanup candidates, whitelist, browser cache protection, or asks what is safe to delete.
metadata:
  short-description: Safely manage Mole cleanup
---

# Mole Management

Use this skill to inspect disk pressure and manage Mole cleanup without deleting user data by accident.

## Ground Rules

- Start with evidence: current disk usage, large directories, and Mole dry-run output.
- Treat `mo clean` as destructive. Run `/opt/homebrew/opt/mole/bin/mo clean --dry-run` first and summarize `$HOME/.config/mole/clean-list.txt`.
- On this machine, `/opt/homebrew/bin/mo` may be another tool. Prefer `/opt/homebrew/opt/mole/bin/mo` for Mole.
- Never clean browser caches or profiles unless the user explicitly asks after seeing the impact. Chrome, Arc, Vivaldi, Brave, Dia, and Firefox caches are intentionally protected.
- Never remove Docker volumes, app media, model files, VM bundles, or iCloud data without explicit confirmation.
- If `$HOME/.config/mole/whitelist` exists, Mole uses it instead of its internal default whitelist. Keep the internal default protections explicit in that file.

## Workflow

1. Snapshot space:
   - `df -h /System/Volumes/Data`
   - targeted `du -sh` checks for known heavy areas, not a blind filesystem walk.
2. Confirm Mole wiring:
   - `brew info mole`
   - `/opt/homebrew/opt/mole/bin/mo --version`
   - verify `$HOME/.config/mole/whitelist` before editing it.
3. Review candidates only:
   - `/opt/homebrew/opt/mole/bin/mo clean --dry-run`
   - read `$HOME/.config/mole/clean-list.txt`
   - group proposed deletes by app/cache family and call out anything surprising.
4. Update whitelist conservatively:
   - Read `references/mole-cleanup.md` before changing whitelist behavior.
   - Preserve Mole's internal default protection patterns when a custom whitelist exists.
   - Add only specific protections that match the user's stated policy.
5. Clean only after confirmation:
   - Use targeted commands for known safe categories when possible.
   - For Homebrew, prefer `brew cleanup -s`; remove `~/Library/Caches/Homebrew/downloads/*` only when the user opted in.
   - For Playwright, remove `~/Library/Caches/ms-playwright` only when the user opted in.
   - For Docker, run `docker system df`, then `docker system prune -af` and `docker builder prune -af`; keep volumes unless explicitly approved.
6. Report:
   - before/after disk usage
   - what was removed or only proposed
   - files changed
   - rollback path for config edits

## When Answering "What Would Be Deleted?"

Run a fresh dry-run with the current whitelist, then summarize from `$HOME/.config/mole/clean-list.txt`. Do not infer from old output.
