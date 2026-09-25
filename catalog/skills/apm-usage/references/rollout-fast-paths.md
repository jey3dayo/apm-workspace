# Rollout Fast Paths — apm 0.31.0-specific procedures

Detailed, version-specific procedures referenced by `SKILL.md` Fast Paths and
Guardrails. Re-check these against the installed `apm` version before relying
on them. Each section says which parts were re-checked on 0.31.0; the rest
were observed on 0.29.0 and carried forward.

## SHA-pin bump sequence (Fast Path 5 / Fast Path 7)

When you bump a SHA pin in `apm.yml` by hand, `mise run deploy` alone does not
pick it up: `apply` stages external skills from the existing lock records and
`apm_modules/`, so the lockfile and the deployed target both stay on the old
commit while every command exits zero. Run `apm install -g --only apm`, then
`mise run deploy`. The install re-resolves a dependency whose manifest ref
differs from the locked one (`detect_ref_change`, observed on 0.31.0 with a
single dependency).

`mise run upgrade` also moves the lock to a hand-bumped SHA on 0.31.0, but it
is the wrong tool here. Besides refreshing every unpinned dependency, it
rewrites every declared SHA pin whose upstream has an annotated semver tag to
the highest such tag's commit, which can be older than the pinned commit, and
appends `# <tag>` to that line.

`apm install -g --only apm` bypasses `mise run apply` the same way the bare
`apm install -g` in Fast Path 6 does, so check the agmsg roster links per
that path's note before calling the refresh done. If the follow-up
`mise run deploy` fails at its `check` stage, it never reaches `apply`, so
the roster links stay unrestored — fix the `check` failure and rerun
`deploy` (or `mise run apply`) rather than assuming the earlier call
recovered them.

For a checked-out external dependency (Fast Path 7) that is SHA-pinned, bump
the pin in `apm.yml` to the pushed commit and follow this same sequence.

## `apm uninstall -g` side effects (Fast Path 9)

Fast Path 9's default is hand-editing `apm.yml` plus `apm lock -g`. `apm
uninstall -g <manifest-ref>` is the alternative and carries more side effects
on 0.31.0, so reach for it only when that default does not apply.

The uninstall re-integrates the remaining packages outside `mise run apply`.
On 0.31.0 it rewrites `apm.yml` (drops the comment that follows the removed
entry, such as the next section header, and folds the gist URL) and deploys
the gist under its un-aliased hash name. Unlinking the agmsg roster and
deploying undeclared sub-skills were observed on 0.29.0 and not re-checked.
Edit `apm.yml` until `git diff` shows only the removed line, follow the agmsg
State section of `~/.apm/AGENTS.md`, then run `mise run deploy`, which
removes the undeclared entries.

Some deployed skill directories also hold a copy of the package's `.apm-pin`
cache marker, which the lock does not record. When one does, `apm uninstall`
removes the tracked files, cannot remove the directory, and aborts listing it
(`Uninstall could not remove tracked target files`, reproduced on 0.31.0).
By then it has already removed the package from `apm_modules/` and the
tracked files; `apm.yml` and the lock still declare it. Confirm each listed
path under `~/.claude/skills/` and `~/.agents/skills/` is a real directory
holding only `.apm-pin`, remove that file and the directory, then rerun the
uninstall. The rerun's `Package ... not found in apm_modules/` is expected
and it completes.

## Guardrail details

- `apm audit --ci`: read a finding by its check name and by the absolute path
  it resolves to, never by its count. Run in `~/.apm`, 0.31.0 maps the
  workspace to the user deploy root, so `deployed-files-present` checks the
  real `~/.claude/...` and `~/.agents/...` paths. Every relative lock row is
  resolved against `$HOME`, so the missing list mixes three kinds: rows left
  by skills retired from the catalog or by the opted-out
  `~/.config/opencode/skills` face, stale files inside a live skill, and
  workspace rows (`.agents/skills/<bridge>`, `.apm/skills/...`) that exist
  under `~/.apm` but not under `$HOME`. The target label does not tell them
  apart, so open each path under both `$HOME` and `~/.apm` before treating
  it as a missing runtime file. Do not turn that into a standing rule that
  `apm audit --ci` may be ignored.
- grep wrapper: do not measure what is left on a deployed target with a
  search whose defaults honour `.gitignore` — deployed output is normally
  ignored, and the session's own `grep` may be such a wrapper (`type grep`).
  Sweep with `command grep -rIl <pattern> <root>` or
  `find -L <root> -type f -print0 | xargs -0 grep -Il <pattern>`, keep
  stderr, and open the matches before reporting a count.
