# Rollout Fast Paths — apm 0.31.0-specific procedures

Detailed, version-specific procedures referenced by `SKILL.md` Fast Paths and
Guardrails. Re-check these against the installed `apm` version before relying
on them. Each section says which parts were re-checked on 0.31.0; the rest
were observed on 0.29.0 and carried forward.

## SHA-pin bump sequence (Fast Path 5 / Fast Path 7)

When you bump a SHA pin in `apm.yml` by hand, `validate:workspace` fails `check`
while the pin has no matching `resolved_commit` in `apm.lock.yaml`, and names
the pin. No task re-resolves the root lock: `deploy:pins` (`apm install -g --only
apm`, then `deploy`) and `upgrade` were removed on 2026-11-10 (last version:
commit `0bcce09`). On the native HOME `apm install -g` works on the consumer
`~/.apm`, not on the checkout's lock, so do not run it to update the lock.
Update the pinned entries of `apm.lock.yaml` to the same commits as the pin (or
revert the pin), then review the change with `mise run lock:diff`.

`apm update` rewrites every declared SHA pin whose upstream has an annotated
semver tag to the highest such tag's commit, which can be older than the pinned
commit, and appends `# <tag>` to that line (observed on 0.31.0). A SHA-pinned
dependency therefore stays pinned by hand.

For a checked-out external dependency (Fast Path 7) that is SHA-pinned, bump
the pin in `apm.yml` to the pushed commit under the same constraint.

## Revision-pin failures on `apm update` (re-checked 0.31.0)

On 0.31.0, `apm update` revision-pin rewrite considers **annotated semver tags
only** (peeled `refs/tags/*^{}` from `git ls-remote`). Lightweight release tags
do not count, even when their commits are newer than every annotated tag.

When a SHA-pinned dependency's highest annotated tag points at an old package
layout, `apm update` can fail during integration — not only move the pin
backward. A typical symptom is `Invalid APM package … no apm.yml, SKILL.md,
hooks, or plugin structure` for a dependency that installs cleanly at HEAD.

Triage:

1. Run `apm update -g --dry-run` and note revision-pin rewrites (`ref: <sha> ->
<sha> (<tag>)`) for the failing package.
2. On the upstream repo, run `git ls-remote <url> 'refs/tags/*'` and check
   which semver tags have a matching `^{}` line (annotated). Compare that
   commit to the manifest SHA and to `main`.
3. If the annotated tag commit is stale but `main` (or a lightweight tag) has
   the intended `skills/` bundle, switch the manifest to branch tracking
   (`git:` + `ref: main`) so revision-pin rewrite no longer applies. Record the
   reason in `docs/package-decisions.md`. The lock still records
   `resolved_commit` at install time.
4. If the dependency must stay SHA-pinned, bump the pin by hand and use the
   SHA-pin bump sequence above instead of `apm update`.

Workspace precedent: `ibelick/ui-skills` (`docs/package-decisions.md`,
2026-09-28).

## `apm uninstall -g` side effects (Fast Path 9)

Fast Path 9's default is hand-editing `apm.yml`. `apm uninstall -g
<manifest-ref>` is the alternative and carries more side effects on 0.31.0, so
reach for it only when that default does not apply.

The uninstall re-integrates the remaining packages by itself.
On 0.31.0 it rewrites `apm.yml` (drops the comment that follows the removed
entry, such as the next section header, and folds the gist URL) and deploys
the gist under its un-aliased hash name. Unlinking the agmsg roster and
deploying undeclared sub-skills were observed on 0.29.0 and not re-checked.
Edit `apm.yml` until `git diff` shows only the removed line, follow the agmsg
State section of the checkout's `AGENTS.md`, then roll out with section B of
`docs/native-distribution.md`.

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
  it resolves to, never by its count. Run in the checkout (observed on 0.31.0 while the checkout was `~/.apm`; not re-checked
  elsewhere), it maps the workspace to the user deploy root, so `deployed-files-present` checks the
  real `~/.claude/...` and `~/.agents/...` paths. Every relative lock row is
  resolved against `$HOME`, so the missing list mixes three kinds: rows left
  by skills retired from the catalog or by the opted-out
  `~/.config/opencode/skills` face, stale files inside a live skill, and
  workspace rows (`.agents/skills/<bridge>`, `.apm/skills/...`) that exist
  under the checkout but not under `$HOME`. The target label does not tell them
  apart, so open each path under both `$HOME` and the checkout before treating
  it as a missing runtime file. Do not turn that into a standing rule that
  `apm audit --ci` may be ignored.
- grep wrapper: do not measure what is left on a deployed target with a
  search whose defaults honour `.gitignore` — deployed output is normally
  ignored, and the session's own `grep` may be such a wrapper (`type grep`).
  Sweep with `command grep -rIl <pattern> <root>` or
  `find -L <root> -type f -print0 | xargs -0 grep -Il <pattern>`, keep
  stderr, and open the matches before reporting a count.
