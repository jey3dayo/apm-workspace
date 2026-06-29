---
name: macos-troubleshooting
description: Diagnose and repair local macOS problems with safe, reversible steps first. Use when the user says Mac, macOS, Finder, Dock, Spotlight, IME, input source, Japanese input, notifications, Bluetooth, audio, permissions, app launch failure, `.appが起動できない`, `Codex.appが起動できない`, `~/.codex`, `logs_2.sqlite`, local SQLite/config/state file recovery, `ファイルを戻して`, CLIで権限や許可を与える相談, or another local system feature is broken, stuck, behaving oddly, or may be fixable by restarting a process or service. For slow, frozen, CPU-heavy, file-descriptor, or process-pressure symptoms, use `pc-ops` instead.
---

# macOS Troubleshooting

Use this skill to turn vague macOS symptoms into a short, safe repair sequence. Prefer reversible process or service restarts before settings resets, logout, or reboot. Keep destructive cleanup, preference deletion, database deletion, and data loss risks behind explicit user confirmation.

## Workflow

1. Identify the affected layer:
   - App-only: one application, browser, editor, or terminal.
   - User agent: menu extras, input, Dock, Finder, Spotlight, notifications.
   - System service: Bluetooth, audio, network, permissions, login items.
   - Data/config: learned dictionaries, caches, preferences, indexes.
   - Local app state: SQLite databases, local config, logs, and restorable state files such as `~/.codex/logs_2.sqlite`.
   - If the symptom is broad, first narrow what fails: one app vs every app, UI search vs file search, input conversion vs input switching, or device connection vs system settings.
2. Inspect before changing:
   - Use `ps`, `launchctl`, `log`, `defaults`, or app-specific checks when they are relevant.
   - Confirm a process or service exists before restarting it. Prefer restarting the narrowest observed process over a guessed or broad service name.
   - Prefer `rg` for searching local notes or case references.
   - When available in a repo or workspace, follow its command wrapper policy.
3. Repair in safe order:
   - Restart the narrowest process or agent.
   - Re-check whether the process came back or the symptom changed.
   - Reset user-level state only when the symptom points to corrupted learning, cache, preference, or index state.
   - Recommend logout or reboot only after narrower actions fail or when macOS requires it.
4. Report exactly what was tried, what changed, and what remains.
5. Add reusable findings to the case reference when the user asks to preserve the knowledge or the case is clearly reusable.

## Case Reference

Read `references/cases.md` before acting when the symptom matches an existing case, or after resolving a new recurring case to append a concise entry.

Case entries should include:

- Symptom
- Likely layer
- Safe actions
- Escalation path
- Observed process or service names
- Date and macOS version when known

## Guardrails

- Do not delete preferences, caches, indexes, dictionaries, or databases without explaining the blast radius and getting confirmation.
- Do not kill broad system services when a narrower user agent exists.
- Do not claim a repair worked until the user verifies the symptom or an observable state changed.
- Avoid long generic macOS advice. Give the next concrete command or setting path.
