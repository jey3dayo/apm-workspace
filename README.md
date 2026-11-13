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
- [`docs/skill-inventory.md`](docs/skill-inventory.md): skill lanes and placement.
- [`docs/skill-overlaps.md`](docs/skill-overlaps.md): overlapping skill roles and
  combinations under evaluation.
- [`docs/apm-task-coverage.md`](docs/apm-task-coverage.md): task responsibilities
  and visibility.
- [`docs/native-distribution.md`](docs/native-distribution.md): rollout, manual
  boundaries, and recovery.
- [`docs/saas-connectors.md`](docs/saas-connectors.md): SaaS connection placement.
- [`docs/agents-provenance.md`](docs/agents-provenance.md): curated agent sources
  and distribution.
- [`docs/diagrams/agent-delegation.md`](docs/diagrams/agent-delegation.md):
  delegation diagrams and their verification status.
- [`docs/package-decisions.md`](docs/package-decisions.md): package and lane
  decision history.
- [`docs/learning-ledger.md`](docs/learning-ledger.md): learning outcomes and
  follow-up measurements.

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

| Intent                   | Command                                                                   |
| ------------------------ | ------------------------------------------------------------------------- |
| Validate without rollout | `mise run check`                                                          |
| Format workspace files   | `mise run format`                                                         |
| Roll out a merged commit | `mise run native:sync` (or `mise run native:sync -- --https` without SSH) |

For deployed-state and learning-intake diagnostics, run the hidden `mise run doctor` task.

The real HOME is native. See [`docs/native-distribution.md`](docs/native-distribution.md)
for rollout and recovery details. Verify a Codex skill rollout by checking
`~/.agents/skills/<id>/SKILL.md`.

## External Checkout Changes

1. Edit, verify, commit, and push the upstream checkout.
2. Check `docs/dependency-holds.txt`, update the SHA pin in `apm.yml`, and run
   `mise run upgrade:deps` to regenerate `apm.lock.yaml`. The task lists holds;
   it does not select or exclude packages. Use `mise run upgrade:deps -- --dry-run`
   to preview the command without regenerating the lock.
3. Review the lock diff and run `mise run validate:workspace` to check pins and
   holds. Lock regeneration can also change unrelated version metadata; see the
   open `upgrade:deps` item in [`todo.txt`](todo.txt).
4. Verify, commit, and push the change through a PR. After merge, roll out with
   `mise run native:sync` and verify the deployed skill. See
   [`docs/native-distribution.md`](docs/native-distribution.md) for details and rollback.

Adding or removing an external dependency also requires a decision record in
[`docs/package-decisions.md`](docs/package-decisions.md).
