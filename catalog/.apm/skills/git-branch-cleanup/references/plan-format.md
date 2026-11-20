# Plan format (git-branch-cleanup reference)

This reference is part of `git-branch-cleanup`. Read it together with `SKILL.md` when presenting the Markdown plan in the planning phase. The safety contract in `SKILL.md` always applies.

Show both proposed and excluded rows. Proposed branch rows must be numbered and
have stable IDs for confirmation. Use a table with at least these columns:

| ID  | local ref | upstream ref / remoteref / remote         | local SHA | live remote SHA | same-repo PRs; excluded external rows            | actor / owner / repository       | linked worktrees       | planned commands                                                                                                                                               | force?                        |
| --- | --------- | ----------------------------------------- | --------- | --------------- | ------------------------------------------------ | -------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| 1   | `<local>` | `<upstream>` / `<remoteref>` / `<remote>` | `<sha>`   | `<sha>`         | `#123 MERGED non-draft; external: 1 (#456 fork)` | `<actor>` / `<owner>` / `<repo>` | `clean linked: <path>` | `git -C <checkout> worktree remove -- <exact-path>`; `git -C <checkout> branch -d -- <local>`; `git -C <checkout> push <remote> --delete <remote-branch-name>` | `no; narrow -D fallback only` |

The command column must identify the exact remote and branch refs, and every Git command in it carries `-C <checkout>`. A
`remote-absent` row carries `remote-absent` in the live remote SHA column and
no `git push --delete` in its command column; do not print a placeholder SHA
or a remote command it will not run. Include a
separate exclusion table with the reason (`remote-only`, `other-owner`,
`OPEN`, `DRAFT`, `SHA mismatch`, `default`, `current`, `protected`, `dirty`,
`locked`, `main worktree`, or `ambiguous`). Do not hide uncertainty in prose.
The planned command order must remain worktree removal, local `-d`, then
remote deletion, with the remote step absent on a `remote-absent` row. On a
`remote-present` row the upstream/remote ref is intentionally retained until
the local deletion result is known. If local `-d` needs the narrowly permitted
`-D` fallback, record that conditional fallback in the same row; it is never a
general force authorization.

Show a separate numbered prune-action table for every exact record from the
dry-run preview, including its exact metadata record/path and the planned
native prune command. A branch-row confirmation never confirms any prune
action. Require separate explicit confirmation of the exact prune IDs and
records. Because native prune is repository-wide, it may run only when the
confirmed prune IDs are the complete preview set; otherwise mark prune
`SKIP` because exact targeting cannot be guaranteed.

Stop after presenting the plan. When the proposed table has rows, ask one
question answerable with y or n that states the actual row count, for example:
“提案の 8 行（マージ済み・SHA 一致・clean）を削除しますか？ y/n”. An n deletes
nothing. When the proposed table is empty, ask no y/n.

Do not ask about a row that failed a gate for a reason a human could resolve
(SHA mismatch, no upstream, no same-repository PR) before that y/n. After the
confirmed rows run, after an n, or right away when nothing was proposed, list
those rows once, each with its reason and a suggested action, as a deferred
question. An answer to it is an instruction to resolve the cause, never a
deletion confirmation: once the cause is resolved, make a new plan, and delete
such a row only after it appears in a new proposed table and the user answers y
to that plan.
