# Manifest Style — How `apm.yml` Entries Are Written

Applies to the root `~/.apm/apm.yml` and to repo-local manifests. The lane a dependency belongs to is decided in `SKILL.md`; this file fixes how the entry is written once the lane is chosen. Field validity is upstream's [manifest schema](https://github.com/microsoft/apm/blob/main/docs/src/content/docs/reference/manifest-schema.md).

## `dependencies.apm` entries

- Shorthand is the default: `owner/repo[/path]#<ref>`, with `github.com` omitted (upstream canonical form).
- Use the object form (`git:` + `ref:`) only for a field shorthand cannot carry: `skills:` to install a subset, `alias:`, or a non-GitHub host such as a gist URL.
- External dependencies pin a full 40-character commit SHA. Workspace-owned refs (`jey3dayo/apm-workspace/...`) and self-referencing repo-local skills use `#main` (see Self-Referencing Repo-Local Skills in `SKILL.md`). A trailing `# vX.Y.Z` comment stays as `apm update` writes it.

## Grouping (root `apm.yml`)

- `dependencies.apm` sits under one level of headers written `# --- <group> ---`, with one blank line between groups and none inside a group.
- Groups, in this order: `workspace`, `org-restricted`, `review`, `engineering / writing`, `react`, `design`, `browser / analysis`, `agent tools`, `productivity / research`.
- A new entry joins the group whose purpose matches. Add a group only when none fits, and update the list above in the same change.
- Within a group, entries are ordered case-insensitively by owner (for a URL, the path after the host), then by the rest of the ref.
- `dependencies.mcp` is ordered by `name`, without group headers.

## `dependencies.mcp` entries

Remote servers use `transport: http`. `http` and `streamable-http` deploy identical Claude Code and Codex config (checked on apm 0.31.0), and upstream examples use `http`.

## Comments

Beyond group headers, a comment states a contract or a lasting reason the entry cannot show, such as why a SaaS MCP sits here despite the connector priority in `docs/saas-connectors.md`. Change history belongs in the commit message or `docs/package-decisions.md`.
