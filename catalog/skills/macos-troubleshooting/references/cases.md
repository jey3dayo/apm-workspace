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

## DNS cache stale after resolver or record changes

Date observed: 2026-05-22
macOS version observed: 26.4.1 (25E253)

Symptom:

- A hostname still resolves to an old IP after DNS record changes.
- `/etc/hosts`, VPN, Wi-Fi, or resolver changes do not appear to take effect.
- CLI tools and apps disagree about name resolution.
- Browser behavior remains stale after the system resolver should have changed.

Likely layer:

- macOS DNS cache or `mDNSResponder` state.
- Browser, VPN, proxy, router, upstream DNS, or application-level caches may also be involved.

Safe actions:

1. Inspect the active resolver configuration:
   ```bash
   scutil --dns
   ```
2. Compare system cache and direct DNS results:
   ```bash
   dscacheutil -q host -a name example.com
   dig example.com
   ```
3. Flush the macOS DNS cache and signal `mDNSResponder`:
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```
4. Re-run the same lookup command and ask the user to retry the affected app.

Escalation path:

- Restart the affected app or browser if only that app remains stale.
- Reconnect VPN or Wi-Fi if the resolver path changed.
- Check browser DNS, DNS-over-HTTPS, proxy, router, or upstream DNS cache when system lookup is correct but the app is still wrong.
- Treat broader network resets or reboot as later steps.

Observed process names:

- `mDNSResponder`

Notes:

- DNS flush helps the macOS resolver cache and `mDNSResponder` state. It does not clear every browser, router, VPN, proxy, upstream DNS, or application-specific cache.
- Use the real hostname instead of `example.com` when executing the checks.
