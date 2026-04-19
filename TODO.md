# TODO

## Open Tasks

- [x] Remove stale external sources with no current manifest/runtime usage: `gonta223-humanizer-ja`, `obra-episodic-memory`, `sawyerhood-dev-browser`
- [ ] Migrate or retire remaining skill-only external repos, then remove their source/input/lock entries:
  `benjitaylor-agentation`, `openai-skills`, `vercel-agent-skills`, `vercel-agent-browser`, `ui-ux-pro-max`, `heyvhuang-ship-faster`, `millionco-react-doctor`, `tokoroten-prompt-review`, `nyosegawa-skills`, `anthropics-claude-code`, `trailofbits-agentic-actions-auditor`, `trailofbits-sharp-edges`, `trailofbits-supply-chain-risk-auditor`, `epicenterhq-epicenter`, `mizchi-chezmoi-dotfiles`
- [ ] Migrate or retire remaining external repos that also carry non-skill assets before removal:
  `obra-superpowers`, `openai-codex-plugin-cc`, `lum1104-understand-anything`, `trailofbits-audit-context-building`, `trailofbits-static-analysis`
- [ ] After each removal batch, reconcile `~/.apm/apm.yml` with `mise run migrate-external` and `mise run apply`
- [ ] Refresh `flake.lock` only after the matching source/input entries are gone

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
