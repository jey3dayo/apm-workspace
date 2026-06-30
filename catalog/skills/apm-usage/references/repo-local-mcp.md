# Repo-Local MCP Recommendations

Use this as a routing aid for choosing repository-local MCPs and skills. It is not a complete inventory or enforcement list.

Before changing deployment, inspect the target repository's current `apm.yml`, runtime docs, and actual source tree. Update this memo only when it improves future routing.

## Placement Heuristics

Prefer repo-local configuration for tools that depend on a specific app runtime, browser session, UI workflow, repository credential context, or local service state.

Keep global APM limited to cross-repo foundations such as lightweight notifications, current docs lookup, public research/readers, and core agent bridges.

If a tool is useful in many repositories and does not depend on repo-local runtime state, keeping it global is usually more practical than scattering identical repo-local manifests.

## Recommended Tools By Signal

| Repository signal                                                        | Recommended repo-local tools                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Next.js, React, Vite, or another browser-served frontend                 | Keep common web skills global. Prefer bundled Chrome/browser operation first; add repo-local or on-demand `chrome-devtools` only for DevTools-specific inspection, project login/session state, local runtime coupling, or repeatable browser verification. |
| Tauri app with `src-tauri`                                               | `tauri-mcp-server`, often `chrome-devtools` too                                                                                                                                                                                                             |
| App already using the Agentation toolbar                                 | `agentation-mcp`                                                                                                                                                                                                                                            |
| Terraform modules, environments, or `.tftest.hcl` tests                  | `terraform-style-guide`, `terraform-test`                                                                                                                                                                                                                   |
| Project-specific database, SaaS, observability, or private API workflows | project-specific MCPs                                                                                                                                                                                                                                       |
| One-off visual inspection or desktop automation                          | `peekaboo` or other screen automation MCPs on demand                                                                                                                                                                                                        |
