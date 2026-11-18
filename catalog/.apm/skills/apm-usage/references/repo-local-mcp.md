# Repo-Local MCP Recommendations

Use this as a routing aid for choosing repository-local MCPs and skills. It is not a complete inventory or enforcement list.

Before changing deployment, inspect the target repository's current `apm.yml`, runtime docs, and actual source tree. Update this memo only when it improves future routing.

## Placement Heuristics

Prefer repo-local configuration for tools that depend on a specific app runtime, browser session, UI workflow, repository credential context, or local service state.

Keep global APM limited to cross-repo foundations such as lightweight notifications, current docs lookup, public research/readers, and core agent bridges.

If a tool is useful in many repositories and does not depend on repo-local runtime state, keeping it global is usually more practical than scattering identical repo-local manifests.

## Recommended Tools By Signal

| Repository signal                                                        | Recommended repo-local tools                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Next.js, React, Vite, or another browser-served frontend                 | Keep common web skills global. `chrome-devtools` is already distributed globally. Prefer `claude-in-chrome`/Codex Chrome addon first; use `chrome-devtools` for DevTools-specific depth (Lighthouse, performance trace, heap snapshot) or repeatable browser verification. |
| Tauri app with `src-tauri`                                               | `tauri-mcp-server`; `chrome-devtools` is already distributed globally if DevTools-specific depth is needed on top of `claude-in-chrome`/Codex Chrome addon                                                                                                                 |
| App already using the Agentation toolbar                                 | `agentation-mcp`                                                                                                                                                                                                                                                           |
| Terraform modules, environments, or `.tftest.hcl` tests                  | `terraform-style-guide`, `terraform-test`                                                                                                                                                                                                                                  |
| Project-specific database, SaaS, observability, or private API workflows | project-specific MCPs                                                                                                                                                                                                                                                      |
| One-off visual inspection or desktop automation                          | Screen automation MCPs on demand; OS-level screenshots use the `screenshot` skill                                                                                                                                                                                          |

## chrome-devtools Exception Documentation

When a repository keeps `chrome-devtools` as an exception to the global default, record the concrete reason in that repository's own `apm.yml`/`AGENTS.md` (e.g. "uses Lighthouse audits for perf regression checks"), not just "this is a web app". Central APM workspace guidance states the default; repo-local docs state the exception and why it does not fit the default.

## chrome-devtools Parallel Sessions (T3 Headless Stewards)

The global declaration distributes `chrome-devtools` without `--userDataDir`, so every session shares the default profile (`~/.cache/chrome-devtools-mcp/chrome-profile`). Chromium allows only one browser process per user data directory (SingletonLock), so parallel sessions cannot use Chrome at the same time. This is by design, not a defect.

`claude-in-chrome` is not the fleet mechanism for headless T3 sessions: it is documented for the interactive CLI and VS Code, stays off under API-key / `setup-token` authentication, and has no multi-session isolation (concurrent sessions compete for the same browser). Do not build parallel-agent browser work on it.

Exception for repositories operated by parallel long-lived agents (product stewards):

- Declare `chrome-devtools` repo-locally in the target repository's `apm.yml`, overriding the global server of the same name, and deliver it with `apm install --only mcp` (see the MCP Ownership Gate in `apm-usage`). Verify the server in the deployed target configuration and the lock fields.
- Give each repository its own persistent profile: `--userDataDir=${HOME}/.cache/chrome-devtools-mcp/profiles/<product>`. Write the path with `${HOME}` expansion, never a literal user home path or user name. Keep `--ignoreDefaultChromeArg=--disable-extensions` so profile extensions (e.g. the password manager needed for passkey sign-in) survive launch.
- Record the reason in the repository's own `apm.yml`/`AGENTS.md` per the exception documentation rule above (e.g. "parallel steward sessions need isolated Chrome profiles; the shared global profile serialises browser work").
- `--isolated` is not a substitute for authenticated work: its temporary profile is deleted when the browser closes, so logins never persist. Reserve it for unauthenticated checks.
- A human performs the first sign-in in each profile, headed, once per origin. Agents do not enter credentials.
