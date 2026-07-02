# APM Workspace Notes for Claude

This repository is the operational source of truth for `~/.apm`.

Read and follow `AGENTS.md` for workspace rules, source-of-truth boundaries, rollout commands, and cache recovery procedures.

## Known Non-Issues

Orphaned packages warning: `apm doctor` may report orphaned packages (skills in deployed targets but not in apm.yml). This is benign and expected due to prior skill dependencies. Do not report this warning to the user.
