# Execution revalidation (git-branch-cleanup reference)

This reference is part of `git-branch-cleanup`. The parent session reads it together with `SKILL.md` only after the user confirms a plan with y. The planning subagent never reads or runs this phase. Two definitions this phase reuses live in [candidate-construction.md](candidate-construction.md), so read those sections before running the gate below: the same-repository partition rule (step 1 of candidate construction) and the all-page rules query with its exit-status, array, and flatten checks (step 3).

Only after the user's y, process the proposed rows one at a time. Immediately
before each deletion, independently re-resolve and compare the live state with
that row:

- checkout top-level and common Git directory from the same `rev-parse`
  command as planning;
- repository, default branch, protected branch set, authenticated actor, parsed
  base repository owner, and current branch;
- both exact upstream metadata fields (`%(upstream)` and
  `%(upstream:remoteref)`) and their resolved remote mapping;
- local ref and SHA;
- authoritative remote ref and SHA from a fresh targeted
  `git -C <checkout> ls-remote --heads <resolved-remote> <validated-upstream:remoteref>`,
  re-confirming `remote-absent` when the fresh query returns no row;
- candidate-level rules from a fresh run of the all-page rules query defined
  in [candidate-construction.md](candidate-construction.md) (step 3), with the
  same exit-status, array, and flatten checks;
- every branch-name-matching PR from a fresh targeted query:

  ```bash
  gh pr list --repo <nameWithOwner> --state all --head <remote-branch-name> --limit 1000 --json number,state,isDraft,headRefName,headRefOid,headRepositoryOwner,headRepository,mergedAt,url
  ```

  Keep the complete `--json` value as one shell token on this line. Partition
  the fresh rows with the same-repository rule used during planning, record
  every excluded fork/other-repository row and its count, and gate only on the
  same-repository rows. Recount the fresh rows: exactly 1000 is
  saturated/ambiguous and `SKIP`; fewer than 1000 may proceed only after a
  successful query. Require at least one same-repository row, and require
  every same-repository row to be merged, non-draft, and SHA-equal. The
  owner/repository checks still use the parsed base owner/repository, not the
  actor; and

- all related worktrees from a fresh `git -C <checkout> worktree list --porcelain` read plus
  fresh tracked/untracked status checks.

This is a per-candidate gate, not a batch check. If any branch identity, SHA,
protection result, same-repository PR row, or worktree value changed, a new
same-repository PR appeared, an OPEN/DRAFT same-repository PR exists, or any
value needed for those checks became unknown, mark only that row
`SKIP_CHANGED` or `SKIP_UNSAFE` and do not delete it. A fork/other-repository
row may appear or change without vetoing the candidate; record it and keep it
outside the matching set. Do not silently update the plan or use an old SHA.

For a row that still passes, use `$git-worktree`, validate the installed
native syntax, and perform operations in this order:

1. Remove each related clean linked worktree with the exact native argv
   `git -C <checkout> worktree remove -- <exact-absolute-path>` and no force flag. If `--` is
   unsupported, use the validated argv-safe form
   `git -C <checkout> worktree remove <exact-absolute-path>` from the installed Git help. If
   any removal fails, stop that row and leave its remote and local branches in
   place. Never remove the main/current/locked/dirty worktree.
2. After all worktrees for the row have been removed, repeat the branch,
   authoritative remote, candidate-level rules, and matching-PR live checks
   from the revalidation gate, including the exact owner/repository checks and
   the 1000-row saturation check. If anything changed or became unknown,
   report the row as `SKIP_CHANGED` or `SKIP_UNSAFE`, keep both branches in
   place, and do not continue.
3. Delete the local branch first with the exact argv equivalent of
   `git -C <checkout> branch -d -- <local-branch>`. On a `remote-present` row this runs while
   the upstream/remote ref is still present; a `remote-absent` row does not
   depend on that ref existing. If `-d` fails specifically because the graph does not mark a
   squash/rebase merge as an ancestor, permit the narrow fallback
   `git -C <checkout> branch -D -- <local-branch>` only when the immediately preceding live
   evidence still proves all same-repository PRs are merged, non-draft, and
   same-owner/same-repository, with every head SHA equal to the local SHA, and
   equal to the remote SHA as well on a `remote-present` row. On a
   `remote-absent` row the exact ref must still be absent from a fresh
   successful `ls-remote`; a failed query is not absence. The row must have been in the plan the user confirmed with y. Do not use `-D`
   for a mismatch, unknown state, failed worktree removal, remote failure, or
   an unmerged/OPEN/DRAFT PR. If local deletion fails for any other reason, or
   the permitted fallback fails, stop the row there; on a `remote-present` row
   that means stopping before remote deletion and keeping the remote branch,
   and on a `remote-absent` row there is no remote step to stop.
4. A `remote-absent` row has no remote mutation. Repeat the candidate-level
   rules and fresh same-repository PR gate, confirm from a fresh successful
   `ls-remote` that the exact ref is still absent, then report remote deletion
   as `NOT_REQUIRED` and finish the row; it never reaches step 5. If that fresh
   query fails or the ref reappeared, still report the local action as
   `DELETED` — it already happened in step 3 — and report the remote action as
   `SKIP_UNSAFE` (query failed) or `SKIP_CHANGED` (ref reappeared). Do not
   delete the reappeared remote ref, and do not collapse the row into a single
   skipped result that hides the completed local deletion.

   For a `remote-present` row, immediately before remote mutation, re-resolve
   the exact upstream remote, its single push URL (the same check as step 4 of
   "Resolve the repository and live context"), and its authoritative SHA, and repeat the
   candidate-level rules and fresh same-repository PR gate. With the local ref
   now gone, compare the remote and every same-repository PR head SHA with the
   confirmed row SHA. If anything
   changed or became unknown, report local deletion as complete and remote
   deletion as `SKIP_CHANGED`/`SKIP_UNSAFE` and `PRESERVED`; do not delete the
   remote branch.

5. For a `remote-present` row only, delete the exact upstream branch from the
   exact resolved remote with the same `<remote-branch-name>` derived from the
   validated `%(upstream:remoteref)`. Never report a `remote-absent` row's
   missing remote branch as `PRESERVED` or recoverable — there is nothing
   there to preserve:

   ```bash
   git -C <checkout> push <remote> --delete <remote-branch-name>
   ```

   If this remote deletion fails, stop that row and report local deletion as
   `DELETED`, remote deletion as `FAILED`, and the remote branch as
   `PRESERVED` and recoverable. Never conceal that partial state or retry by
   silently changing the confirmed row.

Align failure reports with the order: a worktree-removal failure leaves both
branches preserved; a failed post-worktree live gate leaves both branches
preserved; a local `-d`/permitted `-D` failure reports the local action as
`FAILED`, leaves the remote preserved, and reports remote deletion as `SKIP`;
and a remote failure after local deletion reports the local branch deleted but
the remote branch preserved/recoverable. On a `remote-absent` row there is no
remote branch to preserve: report the remote action as `NOT_REQUIRED` when a
fresh successful `ls-remote` confirmed the ref is still absent, and as
`SKIP_CHANGED` (ref reappeared) or `SKIP_UNSAFE` (query failed) otherwise —
never as preserved or recoverable, and report those remote outcomes
independently of how local deletion went. The local action always keeps its
actual result: `FAILED` when step 3 failed, not run at all when the row
stopped earlier, and `DELETED` only in the step 4 branch that runs after step
3 succeeded. Never collapse a row into a single skipped result that hides a
local deletion that already happened. Report each worktree action, local
action, and remote action separately.

Do not run prune merely because branch rows were confirmed or processed. If
prune IDs were separately confirmed, immediately run a new
`git -C <checkout> worktree prune --dry-run --verbose` preview and compare every exact
metadata record/path with the complete confirmed set. If any record is added,
removed, changed, unparseable, or not explicitly confirmed, mark prune
`SKIP` because the repository-wide command cannot target the requested subset.
Only an exact match authorizes the non-forced `git -C <checkout> worktree prune --verbose`
operation; record its output and one outcome for each confirmed prune action.
Report one outcome row per candidate, per worktree action, and per prune action,
using statuses such as `DELETED`, `SKIP_CHANGED`, `SKIP_UNSAFE`, `SKIP`, or
`FAILED`, with the observed refs, SHAs, commands, and failure reason.
