# Codex On macOS

Use this reference when Codex Desktop, Codex CLI, MCP servers, Computer Use, `node_repl`, or the diff UI appears slow, stuck, or repeatedly spawning helpers.

## Initial Checks

Capture Codex-related processes and top CPU first:

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | sort -k5 -nr | sed -n '1,30p'
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | sort -k7 -nr | sed -n '1,30p'
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | rg -i 'Codex|codex|node_repl|Computer Use|mcp-server|npm exec|syspolicyd|trustd|launchservicesd|Falcon|CrowdStrike|jamf'
vm_stat
memory_pressure
```

Check signature state for the main app and any bundled helper app that is part of the hypothesis:

```bash
codesign --verify --deep --strict --verbose=4 /Applications/Codex.app
spctl --assess --type execute --verbose=4 /Applications/Codex.app
codesign --verify --deep --strict --verbose=4 "/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app"
spctl --assess --type execute --verbose=4 "/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app"
```

If available, use the local checker as a limited repair and evidence collection tool:

```bash
~/.config/scripts/check-macos-app.sh --fix
```

Interpretation:

- `valid on disk` and `accepted source=Notarized Developer ID`: signature evaluation is not the current primary failure.
- `invalid signature`, `code or signature have been modified`, or `internal error in Code Signing subsystem`: the app bundle is not trustworthy as installed. Reinstall or replace the app bundle; quarantine or LaunchServices fixes are insufficient.
- High `syspolicyd`, `trustd`, or `launchservicesd` together with invalid signature strongly suggests launch/signature evaluation churn.

## Gatekeeper `Too many open files`

When Codex launch or signature checks show `Too many open files`, test an unrelated executable and evaluator limits before blaming the app bundle:

```bash
spctl --assess --type execute --verbose=4 /bin/ls
sysctl kern.num_files kern.maxfiles kern.maxfilesperproc
launchctl limit maxfiles
log show --style compact --last 30m --predicate 'process == "syspolicyd" AND (eventMessage CONTAINS "100024" OR eventMessage CONTAINS "UNIX error exception" OR eventMessage CONTAINS "Too many open files")'
log show --style compact --last 30m --predicate 'eventMessage CONTAINS "would not allow" AND (eventMessage CONTAINS "MacOS/Codex" OR eventMessage CONTAINS "Resources/codex")'
```

Interpretation:

- `/bin/ls: Too many open files`: `spctl`/`syspolicyd` is failing globally. Do not report this as Codex.app signature proof.
- `/bin/ls: rejected (the code is valid but does not seem to be an app)`: `spctl` is functioning again; this is expected for a non-app executable under this assessment mode.
- `codesign` passes while `spctl` returns `Too many open files`: prioritize SystemPolicy state and leftover Codex helpers over reinstall.
- Low `kern.num_files` relative to `kern.maxfiles` plus `launchctl limit maxfiles` soft limit around 256 points to a per-process evaluator limit, not system-wide file table exhaustion.

Codex Desktop restarts can leave helpers behind. For a clean recovery test, quit Codex, remove Codex helper families, restart `syspolicyd`, then re-measure:

```bash
osascript -e 'quit app "Codex"'
pkill -f '/Applications/Codex.app'
pkill -f 'Codex Computer Use.app'
pkill -f 'codex app-server'
pkill -f 'cua_node/bin/node_repl'
ps -axo pid,ppid,stat,command | rg 'Codex.app|Codex Computer Use|codex app-server|node_repl'
sudo killall syspolicyd
spctl --assess --type execute --verbose=4 /bin/ls
```

Use `sudo killall syspolicyd` only after the Codex process family is stopped; otherwise immediate re-pollution can make the result ambiguous. If this changes `/bin/ls` from `Too many open files` to the expected non-app rejection, treat stale Codex helpers plus wedged `syspolicyd` as the primary finding. Security tools such as Falcon can still be an amplifier, but do not blame them without Endpoint Security pressure, blocked launch/signature logs, or correlation that remains after Codex helpers are gone.

## Diff UI Or Command Startup Hangs

Look for stuck pagers and child chains:

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | rg -i 'git diff|delta|less|codex|node_repl|mcp-server'
```

If `git diff -> delta -> less` is stuck, ask the user to quit the pager with `q` when it is foregrounded, or kill the narrow PID chain when it is orphaned. Re-run the diff in a terminal to separate Git slowness from Codex UI rendering.

## Helper Fan-Out

Multiple Electron renderers and GPU/network utility processes are normal. Many repeated MCP servers, `node_repl`, Computer Use clients, or `npm exec` copies with different elapsed times usually indicate stale sessions or repeated tool activation.

Check whether the copies share the same parent before cleanup:

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | rg -i 'Codex|codex|node_repl|Computer Use|mcp-server|npm exec'
```

Prefer cleanup patterns scoped to Codex helpers:

```bash
pkill -f '/Applications/Codex.app/Contents/Resources/cua_node/bin/node_repl'
pkill -f 'Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app'
pkill -f '@openai/codex/bin/codex.js mcp-server'
pkill -f '@openai/codex/vendor/.*/bin/codex mcp-server'
pkill -f 'npm exec @upstash/context7-mcp'
pkill -f 'npm exec mcp-remote https://mcp.jina.ai'
pkill -f 'npm exec chrome-devtools-mcp'
pkill -f 'npm exec @t09tanaka/mcp-simple-voicevox'
pkill -f 'npm exec @hypothesi/tauri-mcp-server'
pkill -f 'npm exec @steipete/peekaboo'
```

Use a full Codex quit only when narrow cleanup does not stabilize the app or when the user is ready to end the current session:

```bash
pkill -f '/Applications/Codex.app/Contents/MacOS/Codex'
pkill -f 'codex app-server'
```

Re-check after cleanup:

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | rg -i 'Codex|codex|node_repl|Computer Use|mcp-server|npm exec'
```

## Memory Pressure

When the machine shows high memory pressure or Codex appears in the multi-GB range, separate app memory from helper accumulation:

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | sort -k7 -nr | sed -n '1,30p'
ps -axo pid,ppid,rss,command | rg -i 'Codex|codex|node_repl|Computer Use|mcp-server|npm exec'
vm_stat
memory_pressure
```

Interpretation:

- A high Codex renderer or app-server RSS with few helpers points to the active desktop session.
- Many low-to-medium RSS helper processes can add up to several GB and should be treated as fan-out.
- High memory pressure plus high `WindowServer` or browser renderer memory can make Codex diff rendering look broken even when Git itself is fine.
- If Falcon, Jamf, browser, or Slack are the largest processes, report them as competing pressure instead of forcing the Codex hypothesis.

## Reinstall Guidance

If signature validation remains broken after a cask reinstall, recommend a fully closed app and a clean reinstall path. Do not remove app data unless the user explicitly wants a settings reset.

```bash
brew uninstall --cask codex-app
rm -rf /Applications/Codex.app
brew install --cask codex-app
codesign --verify --deep --strict --verbose=4 /Applications/Codex.app
spctl --assess --type execute --verbose=4 /Applications/Codex.app
```

The `rm -rf /Applications/Codex.app` step is destructive to the app bundle and should be user-approved. It does not delete `~/Library/Application Support/Codex` or `~/.codex`.

## Reporting

Report in this order:

1. Whether the specific high-CPU process is gone.
2. Current top remaining CPU offenders.
3. Whether `syspolicyd`/`trustd`/`launchservicesd` are still primary suspects.
4. Whether Codex signature validation passes.
5. Whether repeated helpers remain.
6. The next safest action.
