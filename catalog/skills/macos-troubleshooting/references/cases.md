# macOS Troubleshooting Cases

## Japanese IME conversion inserts "Avatar"

Date observed: 2026-05-22

Symptom:

- Japanese input accepts `あいうえ` normally.
- Extending the input to `あいうえお` surfaces or inserts `Avatar` in the conversion text.
- Candidate UI may show mixed Japanese text and `Avatar`.

Likely layer:

- Japanese IME learning or live conversion candidate state.
- Text input user agents may also be stale, but learning corruption is more likely when the same string repeatedly produces the same bad candidate.

Safe actions:

1. Inspect current input-related processes:
   ```bash
   ps aux | rg 'JapaneseIM|TextInput|Kotoeri|inputmethod'
   ```
2. Restart the Japanese input process when present:
   ```bash
   killall -HUP JapaneseIM-RomajiTyping
   ```
3. Restart input menu agents:
   ```bash
   killall TextInputMenuAgent
   killall TextInputSwitcher
   ```
4. Ask the user to retry the exact text in the same app.

Escalation path:

- If the same bad candidate remains, reset Japanese input conversion learning from System Settings.
- If still broken, remove and re-add the Japanese input source.
- Use logout or reboot only after the narrower actions fail.

Observed process names:

- `JapaneseIM-RomajiTyping`
- `TextInputMenuAgent`
- `TextInputSwitcher`
- `CursorUIViewService`

Notes:

- On current macOS versions, the old `JapaneseIM` process name may not exist. Prefer inspecting first instead of assuming the process name.
