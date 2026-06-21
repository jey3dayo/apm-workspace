---
name: headroom
description: Use when deciding whether to install, enable, or troubleshoot Headroom context compression for local AI agent workflows, especially MCP, proxy, or agent-wrap usage alongside RTK.
---

# Headroom

## Overview

Headroom is a local-first context compression layer for AI agents. Use it when you need to reduce tokens before prompts, tool outputs, logs, RAG chunks, files, or conversation history reach the model.

Treat Headroom as a different layer from RTK:

- RTK compresses CLI command output before it enters the agent transcript.
- Headroom compresses model-facing context through MCP, proxy, library, or agent wrapping.

Use both only when the workflow benefits from both layers. Do not replace RTK with Headroom for ordinary command output filtering.

## Supported Local Targets

Install and enable Headroom only on developer machines where the extra runtime cost is acceptable:

- Windows
- WSL
- macOS

Do not install or enable Headroom on Raspberry Pi or Linux ARM targets unless the user explicitly asks for it.

## Install Management

Manage Headroom through the user-global mise configuration under `~/.config/mise`, not through repository-local tool declarations.

Preferred package:

```toml
[tools]
"pipx:headroom-ai[mcp,proxy]" = "0.26.0"
```

Place that tool only in OS-specific mise config files that target Windows, WSL, or macOS. Keep it out of `config.pi.toml`.

## When To Use

Use Headroom when the user asks for:

- MCP-based context compression
- proxy-based compression for AI clients or SDKs
- agent wrapping for Claude, Codex, Cursor, Aider, or Copilot
- token reduction beyond CLI output filtering
- cross-agent memory or reversible retrieval experiments

For normal tests, builds, git, package manager, and log commands, use RTK first.

## Guardrails

- Start with MCP/proxy support before enabling broad agent wrapping.
- Keep output shaping and learning features opt-in until the user asks for them.
- Do not let `headroom learn` write to `AGENTS.md`, `CLAUDE.md`, or other guidance files without reviewing the exact diff.
- Do not enable Headroom globally on constrained machines such as Raspberry Pi.
- If compressed output hides important detail, retrieve the original context or disable Headroom for that workflow.

## Quick Checks

After installation, verify the local command is available:

```bash
headroom --help
```

For MCP/proxy exploration, prefer a dry, explicit test before wiring it into persistent agent configuration:

```bash
headroom proxy --help
headroom mcp --help
```
