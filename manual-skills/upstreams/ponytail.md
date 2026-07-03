# ponytail

- Upstream: https://github.com/DietrichGebert/ponytail (was `DietrichGebert/ponytail` in root `apm.yml`)
- Moved: 2026-07-03
- Reason: APM's managed rollout mis-deploys ponytail's Claude Code hooks.
  - It converts the package's `copilot-hooks.json` shape (`bash`/`powershell`/`timeoutSec`) into `SessionStart`/`UserPromptSubmit` instead of using the package's own `claude-codex-hooks.json` (`matcher`+`hooks`+`command`/`timeout`), producing invalid hook JSON flagged by `/doctor`.
  - It only tracks the hook entrypoint files in `apm.lock.yaml` `deployed_files` (e.g. `.claude/hooks/ponytail/hooks/ponytail-activate.js`), not the sibling modules those entrypoints `require()` (`ponytail-config.js`, `ponytail-runtime.js`, `ponytail-instructions.js`, `ponytail-subagent.js`), so the hooks crash with `MODULE_NOT_FOUND` after deploy.
- Skills only: `ponytail`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`, `ponytail-review` copied here from `apm_modules/DietrichGebert/ponytail/skills/**` and now ship via the `manual-skills` package + `mise run deploy`.
- Hooks are NOT in this lane (no manual-lane equivalent for hooks in this workspace). They are hand-maintained directly in each target's hook config:
  - `~/.claude/settings.json` (`hooks.SessionStart`, `hooks.UserPromptSubmit`) and `~/.claude/hooks/ponytail/hooks/*.js` (copied from the upstream repo's `hooks/*.js`, all 6 files, not just the 2 entrypoints).
  - Other runtimes that previously received ponytail hooks via APM (`~/.codex/`, `~/.cursor/`, `~/.gemini/`, `~/.kiro/`) were left untouched — their deployed copies simply stop being updated by APM. Not migrated to manual maintenance as part of this change; revisit if they show the same doctor-class breakage.
- To pick up upstream ponytail changes: re-copy `hooks/*.js` from a fresh checkout and re-run the pipe-test steps in the `update-config` skill's "Constructing a Hook" section before trusting the result.
