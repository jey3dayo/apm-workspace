# apm-workspace

Operational workspace for `~/.apm` and the global APM skill rollout. This
checkout—not `~/.config` or deployed runtime directories—is the daily
authoring surface. The `apm` CLI is pinned by `mise`.

## Start Here

- [`AGENTS.md`](AGENTS.md): operational rules, ownership, recovery, and
  verification requirements.
- [`todo.txt`](todo.txt): unfinished work managed with tuxedo; [`done.txt`](done.txt)
  archives completed internal tasks.
- [`docs/skill-inventory.md`](docs/skill-inventory.md): canonical skill-lane
  inventory and placement decisions.
- [`docs/apm-task-coverage.md`](docs/apm-task-coverage.md): task ownership.

## Skill Lanes

Keep this short index here; the inventory above owns the detailed list.

| Need                                            | Authoring surface                  | Delivery                        |
| ----------------------------------------------- | ---------------------------------- | ------------------------------- |
| Global personal skill                           | `catalog/skills/<id>/`             | normal rollout                  |
| Selected repositories only                      | `optional-skills/<id>/`            | consuming repo installs its ref |
| Workspace-only operation                        | `.apm/skills/<id>/`                | tracked runtime bridges         |
| Machine-local override                          | `private-skills/.apm/skills/<id>/` | local Codex sync only           |
| Upstream skill that cannot use the managed lane | `manual-skills/.apm/skills/<id>/`  | manual-skills package           |

External global skills and MCP declarations belong in `apm.yml`; their accepted
resolution is `apm.lock.yaml`. `apm_modules/` and deployed targets (including
`~/.agents/skills` and `~/.codex/`) are generated/cache state, never edit them
directly.

## Common Commands

```powershell
cd ~/.apm
mise bootstrap       # first machine setup
mise run deploy      # normal stable rollout
```

| Intent                                      | Command                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------- |
| Validate without deployment                 | `mise run check`                                                          |
| Run deep checks                             | `mise run verify`                                                         |
| Accept upstream updates                     | `mise run upgrade`                                                        |
| Refresh only local Codex skills             | `mise run apply:skills:local`                                             |
| Roll out shared guidance after it is pushed | `mise run prepare:catalog`, `mise run install:catalog`, `mise run doctor` |

Use `deploy` for a stable rollout; `upgrade` deliberately changes accepted
upstream content and requires a lockfile review. A Codex skill change is
verified only after checking `~/.agents/skills/<id>/SKILL.md`.

## External Checkout Changes

1. Edit, verify, commit, and push the upstream checkout.
2. Run `mise run upgrade` here and confirm the resulting lockfile commit.
3. Verify the deployed skill, then review unrelated lock drift separately.

Adding or removing an external dependency also requires a decision record in
[`docs/package-decisions.md`](docs/package-decisions.md).
