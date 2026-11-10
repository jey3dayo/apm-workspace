# apm-workspace

Operational workspace for the global APM skill rollout. This checkout
(`~/src/github.com/jey3dayo/apm-workspace`)—not `~/.config`, deployed runtime
directories, or the APM consumer state in `~/.apm`—is the daily authoring
surface. The `apm` CLI is pinned by `mise`.

## Start Here

- [`AGENTS.md`](AGENTS.md): operational rules, ownership, recovery, and
  verification requirements.
- [`todo.txt`](todo.txt): unfinished work managed with tuxedo; [`done.txt`](done.txt)
  archives completed internal tasks.
- [`docs/skill-inventory.md`](docs/skill-inventory.md): canonical skill-lane
  inventory and placement decisions.
- [`docs/skill-overlaps.md`](docs/skill-overlaps.md): which skill to use when roles
  overlap, and the competing skills still under evaluation.
- [`docs/apm-task-coverage.md`](docs/apm-task-coverage.md): task ownership.

## Skill Lanes

Keep this short index here; the inventory above owns the detailed list.

| Need                                            | Authoring surface                  | Delivery                             |
| ----------------------------------------------- | ---------------------------------- | ------------------------------------ |
| Global personal skill                           | `catalog/.apm/skills/<id>/`        | normal rollout                       |
| Selected repositories only                      | `optional-skills/<id>/`            | consuming repo installs its ref      |
| Workspace-only operation                        | `.apm/skills/<id>/`                | tracked runtime bridges              |
| Machine-local override                          | `private-skills/.apm/skills/<id>/` | not delivered by native distribution |
| Upstream skill that cannot use the managed lane | `manual-skills/.apm/skills/<id>/`  | manual-skills package                |

External global skills and MCP declarations belong in `apm.yml`; their accepted
resolution is `apm.lock.yaml`. `apm_modules/` and deployed targets (including
`~/.agents/skills` and `~/.codex/`) are generated/cache state, never edit them
directly.

## Common Commands

```sh
cd ~/src/github.com/jey3dayo/apm-workspace
mise bootstrap       # first machine setup
```

| Intent                      | Command                                                                                |
| --------------------------- | -------------------------------------------------------------------------------------- |
| Validate without deployment | `mise run check`                                                                       |
| Run deep checks             | `mise run verify`                                                                      |
| Inspect deployed state      | `mise run doctor`                                                                      |
| Roll out a pushed commit    | section B of [`docs/native-distribution.md`](docs/native-distribution.md) (`native:*`) |

The real HOME is native. The legacy writer (`deploy`, `apply`, `upgrade`,
`refresh` and their helper tasks) was removed on 2026-11-10; its last version
is commit `0bcce09`. A Codex skill change is verified only after checking
`~/.agents/skills/<id>/SKILL.md`.

## External Checkout Changes

1. Edit, verify, commit, and push the upstream checkout.
2. Bump the SHA pin in `apm.yml` by hand. No task updates `apm.lock.yaml` now
   (open item in [`docs/package-decisions.md`](docs/package-decisions.md)).
3. Roll out with section B of `docs/native-distribution.md`, verify the deployed
   skill, then review unrelated lock drift separately.

Adding or removing an external dependency also requires a decision record in
[`docs/package-decisions.md`](docs/package-decisions.md).
