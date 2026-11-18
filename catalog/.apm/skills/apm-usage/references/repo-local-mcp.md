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

Exception to the "prefer the runtime Chrome integration first" rows above: repositories operated by parallel T3 stewards use the per-product `chrome-devtools` profile as the main line for authenticated verification (see the Parallel Sessions section below and priority 1 in the `ai-collaboration` instructions).

## chrome-devtools Exception Documentation

When a repository keeps `chrome-devtools` as an exception to the global default, record the concrete reason in that repository's own `apm.yml`/`AGENTS.md` (e.g. "uses Lighthouse audits for perf regression checks"), not just "this is a web app". Central APM workspace guidance states the default; repo-local docs state the exception and why it does not fit the default.

## chrome-devtools Parallel Sessions (T3 Headless Stewards)

The global declaration distributes `chrome-devtools` without `--userDataDir`, so every session shares the default profile (`~/.cache/chrome-devtools-mcp/chrome-profile`). Chromium allows only one browser process per user data directory (SingletonLock), so parallel sessions cannot use Chrome at the same time. This is by design, not a defect.

`claude-in-chrome` is not the fleet mechanism for headless T3 sessions: it is documented for the interactive CLI and VS Code, stays off under API-key / `setup-token` authentication, and has no multi-session isolation (concurrent sessions compete for the same browser). Do not build parallel-agent browser work on it. The same applies to the Codex Chrome addon in Codex sessions: it is the interactive counterpart, not a fleet mechanism, and Codex workers must not be given `claude-in-chrome`-based procedures. The per-product `chrome-devtools` profile is the shared main line for both runtimes, and the repo-local declaration must be verified in both deployed target configurations (Claude and Codex MCP settings).

Exception for repositories operated by parallel long-lived agents (product stewards):

- Declare `chrome-devtools` repo-locally in the target repository's `apm.yml`, overriding the global server of the same name, and deliver it with `apm install --only mcp` (see the MCP Ownership Gate in `apm-usage`). Verify the server in the deployed target configuration and the lock fields.
- Give each repository its own persistent profile: `--userDataDir=${HOME}/.cache/chrome-devtools-mcp/profiles/<product>`. Write the path with `${HOME}` expansion, never a literal user home path or user name. Keep `--ignoreDefaultChromeArg=--disable-extensions` so profile extensions (e.g. the password manager needed for passkey sign-in) survive launch.
- Keep any repo-side note minimal and generic, or omit it: the declaration is self-evident, and internal operation terms (e.g. "steward") or procedures (first sign-in, credential handling) do not belong in company repositories — reviewers there cannot act on them. The detail lives in this document; a one-line PR-body note is enough.
- `--isolated` is not a substitute for authenticated work: its temporary profile is deleted when the browser closes, so logins never persist. Reserve it for unauthenticated checks.
- Agents do not enter credentials (they never learn or type credential values). Operating the profile's password-manager extension (autofill, passkey) is allowed and is not credential entry. A human performs the sign-in, headed, only when a profile is not signed in for an origin — both the first time and after a session expires — and the extension cannot get through. The unit is per profile × origin.
- Once signed in, opening or reloading an authenticated page, triggering SSR, and checking console, network, or logs is verification, not credential entry: the agent does it itself through `chrome-devtools` in its own session, whether or not a separate verification child session exists. Asking a human to open a page in their everyday Chrome is not a substitute. If the `chrome-devtools` tools are not visible in the current session (in Claude, not found even via ToolSearch), arrange a new or reopened session and report that; do not delegate the page open to a human. The selection priority itself lives in the always-loaded `ai-collaboration` instructions (Browser selection), not only in this reference.
