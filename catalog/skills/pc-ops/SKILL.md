---
name: pc-ops
description: Diagnose local PC slowdowns, command-launch delays, stuck developer tools, excessive helper processes, file descriptor pressure, macOS signature evaluation problems, LaunchServices issues, or security-agent interference. Use when the user says the machine, terminal, Codex, IDE, browser, diff UI, MCP servers, or app launch is slow, frozen, unusually CPU-heavy, or needs safe investigation and repair. Do not use for local SQLite/config/state file recovery such as `~/.codex/logs_2.sqlite` or backup restore requests; use `macos-troubleshooting` for reversible local state repair.
---

# PC Ops

Use this skill to turn a vague "the PC is slow or broken" report into a measured local diagnosis, then propose the narrowest safe fix. Prefer observation before killing processes, and prefer reversible process cleanup before cache deletion, app reinstall, logout, or reboot.

## Workflow

1. Capture the symptom in concrete terms:
   - What is slow: command startup, terminal prompt, app launch, diff rendering, browser UI, whole desktop, network, or one tool.
   - Scope: one app, one repo, one terminal, all shells, all GUI apps, or the whole machine.
   - Timing: just after reboot, after app reinstall, after many agent sessions, after security software update, or after long uptime.
2. Check saturation before changing anything:
   - CPU and memory top processes.
   - Process fan-out for the affected app.
   - File descriptor counts when commands fail to start or apps hang.
   - Stuck child process chains such as `git diff -> pager`, test runners, language servers, MCP servers, or browser helpers.
   - macOS service pressure from `syspolicyd`, `trustd`, `launchservicesd`, `WindowServer`, `mds`, `spotlightknowledged`, MDM, or endpoint security agents.
3. Classify the likely layer:
   - App/runtime fan-out: many helper processes, MCP servers, renderers, Node processes, or stale children.
   - Shell/repo-specific: slow prompt hooks, `git status`, huge repo, stuck pager, or broken filesystem watch.
   - macOS trust/launch: `syspolicyd`, `trustd`, `spctl`, `codesign`, quarantine, or LaunchServices.
   - UI compositor: `WindowServer`, screen recording, external display, browser/video conferencing, or GPU service.
   - Security/MDM: Falcon, Jamf, VPN, DLP, or other corporate agents.
4. Act in safe order:
   - Stop a confirmed stuck command or narrow helper process first.
   - Restart only the affected app or helper group before broader system actions.
   - Use app-specific validation such as `codesign`/`spctl` before recommending reinstall.
   - Ask before deleting caches, preferences, indexes, app data, or generated state that could remove user configuration.
5. Re-measure after every material change and compare against the prior snapshot.
6. Report with evidence: top offenders, commands run, what changed, remaining risk, and the next single action.
7. If the issue is resolved and the finding is likely reusable, ask a short follow-up such as: "この原因と対処を `pc-ops` に追記しますか？" Do not edit the skill or memory unless the user agrees.

## Boundary With macOS Troubleshooting

Use `pc-ops` for performance and execution-environment symptoms: slow commands, freezes, CPU or memory pressure, file descriptor pressure, excessive helper processes, app launch latency, Gatekeeper/signature evaluation delays, and security-agent interference.

Use `macos-troubleshooting` instead for app launch failure without a performance angle, local database/config/state file recovery, `~/.codex` SQLite recovery, or "restore this file" requests.

## Snapshot And Re-Measure

For any suspected runaway, leak, or leftover-process case, take a snapshot before acting and repeat the same snapshot after cleanup or 3-5 minutes later. Treat a process as a cleanup candidate only when the evidence supports it:

- CPU remains high across snapshots without an expected active task.
- RSS keeps growing, memory pressure is warning/critical, or swap/compression increases.
- The parent process is gone, the helper is old, or many copies of the same helper remain.
- The user is no longer using the app/session that owns the helper.
- A narrower app restart or helper cleanup is likely to be reversible.

## Core Topics

Use these four topics as the default mental checklist. The user may only mention one symptom, but local slowdowns often involve more than one layer.

### Resource Runaway Detection

Look for one process or process family consuming unusual CPU, GPU, file descriptors, disk I/O, or process count. Capture both the global top offenders and a filtered view for the affected tool. Pay attention to elapsed time: a newly spawned process at high CPU suggests active work, while many old children with low CPU suggest leaks or stale sessions.

### Broken `.app` Bundle

Suspect app bundle damage when a GUI app starts slowly, helpers fail to launch, `syspolicyd`/`trustd`/`launchservicesd` are active, or reinstall/quarantine fixes only partly help. Use `codesign` and `spctl` as evidence. Treat invalid signatures as reinstall/replace problems, not as cache problems.

### Memory Pressure

Check memory pressure when Activity Monitor or widgets show high memory use, swap growth, compressed memory, or app memory in multiple GB. A single large RSS process may be acceptable; the bad sign is pressure plus swap/compression plus UI or command latency. Report top resident-memory processes separately from CPU top processes.

### Leftover Processes

Look for stale child processes after agent sessions, test runs, browsers, MCP servers, language servers, terminals, or app restarts. Confirm parent-child relationships before killing. Prefer narrow cleanup by process family, then re-check that the count actually dropped.

## macOS Command Set

Use these patterns as starting points and adapt them to the user request. Avoid broad kills until a specific process family is identified.

```bash
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | sort -k5 -nr | sed -n '1,30p'
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | sort -k7 -nr | sed -n '1,30p'
ps -axo pid,ppid,stat,etime,%cpu,%mem,rss,command | rg -i 'app-name|tool-name|mcp|node|syspolicyd|trustd|launchservicesd'
lsof -nP | awk 'NR>1 {pid=$(1+1); count[pid]++; cmd[pid]=$(1)} END {for (pid in count) print count[pid], pid, cmd[pid]}' | sort -nr | sed -n '1,30p'
vm_stat
memory_pressure
launchctl limit maxfiles
ulimit -n
```

For app signature or Gatekeeper suspicion:

```bash
codesign --verify --deep --strict --verbose=4 /Applications/App.app
spctl --assess --type execute --verbose=4 /Applications/App.app
xattr -p com.apple.quarantine /Applications/App.app 2>/dev/null
```

If the user has `~/.config/scripts/check-macos-app.sh`, mention it only when the target is a macOS `.app` bundle and quarantine, LaunchServices, or signature evaluation is part of the hypothesis:

```bash
~/.config/scripts/check-macos-app.sh --fix /Applications/App.app
```

Treat that script as a targeted verifier and limited repair tool. It can clear quarantine and refresh LaunchServices when designed to do so, but it cannot repair an actually invalid code signature; recommend reinstalling the app bundle when `codesign` reports modified code or invalid signature.

## Codex And Agent Tools

When the symptom involves Codex, MCP, Computer Use, node repl, or a missing diff UI, read `references/codex-macos.md` before acting.

## Guardrails

- Do not delete caches, preferences, LaunchServices databases, Spotlight indexes, app support directories, or agent state without explicit confirmation.
- Do not blame security software only from memory size. Look for CPU, Endpoint Security pressure, blocked launch/signature logs, or correlation with `syspolicyd`/`trustd`.
- Do not claim a reinstall fixed the issue until `codesign`, `spctl`, and a fresh process snapshot agree.
- Do not leave the user with a broad command when a narrower `pkill -f` pattern or PID is known.
- If a command requires elevated permissions or cannot run inside the current sandbox, state that clearly and provide the exact command for the user or request approval when available.
