# Rollout Fast Paths — apm 0.29.0-specific procedures

Detailed, version-specific procedures referenced by `SKILL.md` Fast Paths and
Guardrails. Re-check these against the installed `apm` version before relying
on them; they were observed on 0.29.0.

## SHA-pin bump sequence (Fast Path 5 / Fast Path 7)

When you bump a SHA pin in `apm.yml` by hand, `mise run upgrade` cannot do it:
observed on apm 0.29.0, `apm update` refuses to replace a revision pin, and
`mise run deploy` re-applies the lock without re-resolving the manifest, so
the lockfile and the deployed target both stay on the old commit while every
command exits zero. Run `apm install -g --only apm`, then `mise run deploy`.

`apm install -g --only apm` bypasses `mise run apply` the same way the bare
`apm install -g` in Fast Path 6 does, so check the agmsg roster links per
that path's note before calling the refresh done. If the follow-up
`mise run deploy` fails at its `check` stage, it never reaches `apply`, so
the roster links stay unrestored — fix the `check` failure and rerun
`deploy` (or `mise run apply`) rather than assuming the earlier call
recovered them.

For a checked-out external dependency (Fast Path 7) that is SHA-pinned, bump
the pin in `apm.yml` to the pushed commit and follow this same sequence
instead of `mise run upgrade` alone — `apm update` refuses to replace a
revision pin (observed on apm 0.29.0), so `mise run upgrade` alone leaves the
lock and deployed target on the old commit while exiting zero.

## `.apm-pin` residue after uninstall (Fast Path 9)

If the uninstall aborts listing target directories, apm 0.29.0 leaves
`.apm-pin` behind after removing the skill files. Confirm each listed path
under `~/.claude/skills/` and `~/.agents/skills/` is a real directory holding
only `.apm-pin`, remove that file and the directory, then rerun the uninstall.

The uninstall re-integrates the remaining packages outside `mise run apply`:
it rewrites `apm.yml` (drops comments, folds the gist URL), unlinks the
agmsg roster, and deploys undeclared sub-skills and un-aliased gist names.
Edit `apm.yml` until `git diff` shows only the removed line, follow the
agmsg State section of `~/.apm/AGENTS.md`, then run `mise run deploy`, which
removes the undeclared entries.

After the uninstall, check the removed package's deployed commands / agents /
hooks against the real files on disk (`~/.claude/commands`, `~/.cursor/commands`,
`~/.config/opencode/commands`): uninstall only cleans the targets of the
packages that still remain, so files the removed package deployed under a
still-installed package's directory can survive (microsoft/apm#2656). Move
any orphaned files aside rather than deleting them.

## Guardrail details

- `apm audit --ci`: read a finding by its check name and by the absolute path
  it resolves to, never by its count. `deployed-files-present` calls
  `exists()` on `<project_root>/<path>`, and apm 0.29.0 takes `project_root`
  from the current directory: run in `~/.apm` it asks about
  `~/.apm/.claude/...`, while the user-scope rollout lives under
  `~/.claude/...`. A finding there can be about the audit's root rather than
  the deployed runtime, and the runtime is confirmed separately with
  `mise run doctor` and a source-to-target comparison. Do not turn that into
  a standing rule that `apm audit --ci` may be ignored.
- grep wrapper: do not measure what is left on a deployed target with a
  search whose defaults honour `.gitignore` — deployed output is normally
  ignored, and the session's own `grep` may be such a wrapper (`type grep`).
  Sweep with `command grep -rIl <pattern> <root>` or
  `find -L <root> -type f -print0 | xargs -0 grep -Il <pattern>`, keep
  stderr, and open the matches before reporting a count.
