---
name: git-branch-cleanup
description: >-
  Safely plan and, only after explicit confirmation of exact plan rows, clean
  merged local branches, their matching upstream branches, and clean linked
  worktrees. Use for post-merge Git branch cleanup; do not use for remote-only,
  other-owner, or ambiguous branch deletion.
---

# Git Branch Cleanup

Use this skill for evidence-based cleanup after pull requests are merged. The
default result is a Markdown plan. The plan may include deletion commands, but
the first pass never deletes a branch or worktree.

Read and use `$git-worktree` before any worktree operation. That skill owns
`git wt` versus native `git worktree` syntax and worktree diagnosis; this skill
owns the branch/PR safety contract, candidate evidence, confirmation boundary,
and deletion order.

## Safety contract

- Treat every invocation as `plan-only` until the user explicitly confirms the
  exact plan row IDs, branch refs, and SHAs to mutate. “Clean up branches” is
  not confirmation. A confirmation for a stale plan is invalid; make a new
  plan.
- The automatic candidate set is a local branch with one unambiguous upstream
  branch on a resolved remote. A remote-only branch is never an automatic
  candidate.
- The parsed base repository owner, same-repository PR head repository
  identity, base repository, local branch SHA, upstream remote SHA, and every
  same-repository matching PR head SHA must be known and agree. External rows
  are recorded separately and are never evidence for deletion. The
  authenticated GitHub actor must also be known, but is recorded separately
  from the base repository owner; do not require a human actor to be the owner
  of an organization-owned repository. Unknown, divergent, or ambiguous state
  in the gating set is `SKIP`.
- Exclude the default branch, current branch, every protected branch, and any
  branch whose related worktree is the main worktree, current worktree,
  locked, dirty, unreadable, or otherwise ambiguous.
- A dirty worktree includes any tracked or untracked file reported by
  `git status --porcelain=v1 --untracked-files=all`.
- Partition PRs whose head branch matches the candidate into same-repository
  rows and fork/other-repository rows. Record the count and details of the
  excluded fork/other-repository rows, but do not put them in the matching set
  that gates deletion. Require at least one same-repository row; every such
  row must be `MERGED`, non-draft, and SHA-equal. A same-repository `OPEN`,
  draft, closed-but-unmerged, or otherwise unresolved row excludes the
  candidate. Fork/other-repository rows neither veto the candidate nor satisfy
  the at-least-one requirement.
- Only clean linked worktrees can be removed, and only with the exact native,
  non-forced command `git worktree remove -- <exact-absolute-path>` after
  validating the installed Git syntax. If that Git does not accept `--`, pass
  the exact absolute path as its own argv element in the non-forced form
  `git worktree remove <exact-absolute-path>`; never turn the path into a shell
  fragment. Do not use a `git wt` delete operation: it can also delete the
  branch and run `wt.deletehook`. Never pass a force flag to a worktree removal
  command.
- Process a confirmed row in this order: remove its safe linked worktrees,
  delete the local branch with `git branch -d` (or the narrow `-D` fallback
  described below), then delete the remote branch. Keep the remote/upstream
  ref until local deletion completes: it supplies `git branch -d` with its
  mergedness evidence, and a later remote-deletion failure leaves a
  recoverable remote branch. Use `git branch -D` only for the narrow squash or
  rebase case after the same exact SHA and merged-PR evidence has passed live
  revalidation and the user confirmed that row.

## Resolve the repository and live context

Run these checks from the checkout being cleaned. Resolve values; do not assume
`main`, `master`, or `origin`.

1. Confirm that the path is a Git checkout and record its top-level path:
   `git rev-parse --show-toplevel`. Resolve the GitHub repository and default
   branch from GitHub, not from a conventional branch name:

   ```bash
   gh repo view --json nameWithOwner,defaultBranchRef --jq '[.nameWithOwner, .defaultBranchRef.name] | @tsv'
   ```

   Failure to resolve either value makes automatic cleanup unavailable.

2. Resolve the authenticated actor with `gh api user --jq .login`. Record it
   as the actor, and treat an unavailable login as `SKIP`; do not infer actor
   identity from Git config or a remote URL. This actor value is not the base
   repository owner check below.

3. Resolve the current branch with
   `git symbolic-ref --quiet --short HEAD`. A detached HEAD has no automatic
   cleanup candidates. Record the exact current worktree path and common Git
   directory as additional identity checks.

4. Enumerate configured remotes with `git remote` and inspect each fetch URL
   using `git remote get-url <remote>`. For a branch, use its configured
   upstream metadata rather than choosing a name by convention:

   ```bash
   git for-each-ref --format='%(refname:short)%09%(upstream)%09%(upstream:remotename)%09%(upstream:remoteref)%09%(objectname)' refs/heads
   ```

   Select a remote only when its fetch URL resolves to the GitHub repository
   returned above and the branch's upstream metadata names that remote. If a
   remote cannot be mapped, or a branch has no single upstream, mark that
   branch `SKIP`. A remote can be selected per candidate; there is no implicit
   `origin`.

5. Parse the base repository owner from the resolved `nameWithOwner`: require
   exactly one `/` separating two non-empty segments, using the first as the
   owner and the second as the repository name. If it cannot be parsed that
   way, mark the repository `SKIP`. Resolve protected branch names from GitHub.
   If this read fails, do not delete any branch because protected-state is
   unknown:

   ```bash
   gh api --paginate "repos/<nameWithOwner>/branches?protected=true&per_page=100" --jq '.[].name'
   ```

6. Read registered worktrees with `git worktree list --porcelain`, then use
   `$git-worktree` for interpretation and command details. The first porcelain
   worktree record is the main worktree only when that record is non-bare. If
   the first record has `bare`, there is no main worktree; never label a later
   non-bare linked worktree as main in that case. For each worktree record,
   retain its absolute path, branch, lock/prunable markers, and whether it is
   the current worktree. Check cleanliness with:

   ```bash
   git -C <worktree-path> status --porcelain=v1 --untracked-files=all
   ```

   If a related worktree cannot be read or its status cannot be established,
   classify the candidate as `SKIP`.

## Synchronize and construct candidates

First scan the local branch rows and validate their upstream metadata. For a
row to enter the planning set, `%(upstream)` must be exactly a ref under
`refs/remotes/<selected-remote>/...`, where `<selected-remote>` equals
`%(upstream:remotename)`, and `%(upstream:remoteref)` must be exactly one
non-empty `refs/heads/<branch>` ref. Do not turn a missing, non-branch, or
multiply-valued upstream into a deletion candidate.

Define `<remote-branch-name>` exactly as the bare suffix obtained by stripping
the validated `refs/heads/` prefix from `%(upstream:remoteref)`. Preserve the
suffix byte-for-byte, including slashes; do not normalize, decode, or infer a
different name. Use this same value for `gh pr list --head <remote-branch-name>`
during live revalidation and for remote deletion. Use the validated full
`%(upstream:remoteref)` for remote-ref matching.

After the identity checks, fetch-prune each resolved remote represented in the
planning set. This synchronization is allowed in plan-only mode; it does not
authorize branch or worktree deletion. A failed fetch leaves that remote's
candidates in `SKIP`.

The planning pass makes exactly one remote-head query per resolved remote, with
no branch argument:

```bash
git ls-remote --heads <resolved-remote>
```

Parse each complete successful result client-side. For a validated full
`refs/heads/<remote-branch-name>`, require exactly one matching row, then use
its SHA as the authoritative remote SHA. A missing, multiple, malformed, or
divergent result is `SKIP`; do not issue another planning `ls-remote` for that
remote. Resolve each local SHA with `git rev-parse <local-ref>` and require it
to equal the mapped remote SHA.

The planning pass also makes exactly one repository-wide PR query:

```bash
gh pr list --repo <nameWithOwner> --state all --limit 1000 --json number,state,isDraft,headRefName,headRefOid,headRepositoryOwner,headRepository,mergedAt,url
```

Keep the complete comma-separated `--json` value as one shell token on the
same line as `--json`. A failed query cannot establish candidate safety and
leaves all affected candidates in `SKIP`. Count all returned rows: exactly
1000 is saturated/ambiguous and is `SKIP`; fewer than 1000 may proceed only
after successful completion. Match branches client-side by exact
`headRefName == <remote-branch-name>`; do not issue a planning PR query per
branch.

For each validated local branch row:

1. Partition the exact branch-name PR rows into a same-repository set and an
   explicitly excluded external set. A row is same-repository only when
   `headRepositoryOwner.login` equals the parsed base repository owner and
   `headRepository.nameWithOwner` equals the resolved base repository exactly.
   Record every fork/other-repository row, and any row whose repository
   identity is unknown, with its number, state, owner, repository, and SHA;
   record the count separately and exclude those rows from the matching set.
   They do not veto deletion and do not satisfy the requirement below. Require
   at least one same-repository row. Every same-repository row must have the
   exact head branch name, `state == MERGED`, `isDraft == false`, a known
   `headRefOid`, and a `headRefOid` equal to both the local and authoritative
   remote SHA. If the CLI cannot enumerate all repository rows, classify the
   candidate as `SKIP` rather than relying on a partial list. Same-repository
   branch-level human ownership is not exposed reliably; do not infer it from
   the actor, Git config, committer, or branch name. The authenticated actor
   remains separate evidence and is never substituted for the parsed base
   owner.
2. Exclude a local or upstream branch when either name is the resolved default
   branch, the current branch, or a name in the protected baseline. Keep a
   branch with no same-repository merged PR, a remote-only branch, and any
   external-only branch out of the automatic candidate set.
3. For the upstream branch, URL-encode the entire `<remote-branch-name>` as
   one path segment and query the candidate-level rules endpoint:

   ```bash
   gh api "repos/<nameWithOwner>/rules/branches/<URL-encoded-branch>"
   ```

   Interpret only a successful JSON array. An empty array means no applicable
   rule was returned. A non-empty array is valid only when every element has a
   non-empty `type` plus ruleset identity such as `ruleset_id` and
   `ruleset_source`; it means an applicable rule is present and the candidate
   is `protected` for this cleanup. The branch-rules endpoint returns applied
   rule objects rather than ruleset-level `enforcement` metadata, so do not
   require an `enforcement` field. If the query fails, the result is not an
   array, or any returned rule lacks that identity, classify the candidate as
   `SKIP`.
   Combine this candidate-level result with the required protected baseline:
   legacy protection from `branches?protected=true` and ruleset-only
   protection both fail closed. A branch in either set is protected; do not
   delete it. URL-encode slashes and other reserved characters in the branch
   name exactly once.

4. For every related worktree, exclude the candidate if it is the main or
   current worktree, has a `locked` or `prunable` marker, or has any tracked or
   untracked change. Require every related worktree to be clean and safe before
   proposing that candidate; never select only the safe subset of an unsafe
   branch's worktrees.

Before presenting the plan, preview stale worktree metadata without changing
anything:

```bash
git worktree prune --dry-run --verbose
```

Treat each exact prunable metadata record from this preview as its own numbered
prune action, retaining the exact record/path rather than grouping records by
branch or worktree. If the preview fails or cannot produce stable exact
records, record prune as `SKIP`; the branch rows may still be proposed.

Record an evidence object for each candidate and each exclusion. The evidence
must include local ref, both exact `%(upstream)` and
`%(upstream:remoteref)` values, upstream remote, repository, default/current/
protected-baseline and candidate-level rules checks, authenticated actor,
parsed base repository owner, all same-repository PR numbers and states,
excluded external PR count and every excluded row's number/state/owner/
repository/SHA, head owner/repository values, local SHA, remote SHA, head
SHAs, and related worktree paths and status.

## Present the Markdown plan

Show both proposed and excluded rows. Proposed branch rows must be numbered and
have stable IDs for confirmation. Use a table with at least these columns:

| ID  | local ref | upstream ref / remoteref / remote         | local SHA | live remote SHA | same-repo PRs; excluded external rows            | actor / owner / repository       | linked worktrees       | planned commands                                                                                                     | force?                        |
| --- | --------- | ----------------------------------------- | --------- | --------------- | ------------------------------------------------ | -------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| 1   | `<local>` | `<upstream>` / `<remoteref>` / `<remote>` | `<sha>`   | `<sha>`         | `#123 MERGED non-draft; external: 1 (#456 fork)` | `<actor>` / `<owner>` / `<repo>` | `clean linked: <path>` | `git worktree remove -- <exact-path>`; `git branch -d -- <local>`; `git push <remote> --delete <remote-branch-name>` | `no; narrow -D fallback only` |

The command column must identify the exact remote and branch refs. Include a
separate exclusion table with the reason (`remote-only`, `other-owner`,
`OPEN`, `DRAFT`, `SHA mismatch`, `default`, `current`, `protected`, `dirty`,
`locked`, `main worktree`, or `ambiguous`). Do not hide uncertainty in prose.
The planned command order must remain worktree removal, local `-d`, then
remote deletion. The upstream/remote ref is intentionally retained until the
local deletion result is known. If local `-d` needs the narrowly permitted
`-D` fallback, record that conditional fallback in the same row; it is never a
general force authorization.

Show a separate numbered prune-action table for every exact record from the
dry-run preview, including its exact metadata record/path and the planned
native prune command. A branch-row confirmation never confirms any prune
action. Require separate explicit confirmation of the exact prune IDs and
records. Because native prune is repository-wide, it may run only when the
confirmed prune IDs are the complete preview set; otherwise mark prune
`SKIP` because exact targeting cannot be guaranteed.

Stop after presenting the plan and ask for confirmation of exact rows, for
example: “Confirm rows 1 and 3 exactly as shown, including their refs and
SHAs.” Do not treat confirmation of a branch prefix, a PR number alone, or a
general cleanup request as row confirmation.

## Revalidate and execute confirmed rows

Only after exact row confirmation, process rows one at a time. Immediately
before each deletion, independently re-resolve and compare the live state with
that row:

- repository, default branch, protected branch set, authenticated actor, parsed
  base repository owner, and current branch;
- both exact upstream metadata fields (`%(upstream)` and
  `%(upstream:remoteref)`) and their resolved remote mapping;
- local ref and SHA;
- authoritative remote ref and SHA from a fresh targeted
  `git ls-remote --heads <resolved-remote> <validated-upstream:remoteref>`;
- candidate-level rules from a fresh
  `gh api "repos/<nameWithOwner>/rules/branches/<URL-encoded-branch>"` query;
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

- all related worktrees from a fresh `git worktree list --porcelain` read plus
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
   `git worktree remove -- <exact-absolute-path>` and no force flag. If `--` is
   unsupported, use the validated argv-safe form
   `git worktree remove <exact-absolute-path>` from the installed Git help. If
   any removal fails, stop that row and leave its remote and local branches in
   place. Never remove the main/current/locked/dirty worktree.
2. After all worktrees for the row have been removed, repeat the branch,
   authoritative remote, candidate-level rules, and matching-PR live checks
   from the revalidation gate, including the exact owner/repository checks and
   the 1000-row saturation check. If anything changed or became unknown,
   report the row as `SKIP_CHANGED` or `SKIP_UNSAFE`, keep both branches in
   place, and do not continue.
3. Delete the local branch first with the exact argv equivalent of
   `git branch -d -- <local-branch>`, while the upstream/remote ref is still
   present. If `-d` fails specifically because the graph does not mark a
   squash/rebase merge as an ancestor, permit the narrow fallback
   `git branch -D -- <local-branch>` only when the immediately preceding live
   evidence still proves all same-repository PRs are merged, non-draft, and
   same-owner/same-repository, with every head SHA equal to both the local and
   remote SHA. The user must have confirmed that exact row. Do not use `-D`
   for a mismatch, unknown state, failed worktree removal, remote failure, or
   an unmerged/OPEN/DRAFT PR. If local deletion fails for any other reason, or
   the permitted fallback fails, stop before remote deletion and keep the
   remote branch.
4. Immediately before remote mutation, re-resolve the exact upstream remote
   and its authoritative SHA, and repeat the candidate-level rules and fresh
   same-repository PR gate. With the local ref now gone, compare the remote and
   every same-repository PR head SHA with the confirmed row SHA. If anything
   changed or became unknown, report local deletion as complete and remote
   deletion as `SKIP_CHANGED`/`SKIP_UNSAFE` and `PRESERVED`; do not delete the
   remote branch.
5. Delete the exact upstream branch from the exact resolved remote with the
   same `<remote-branch-name>` derived from the validated
   `%(upstream:remoteref)`:

   ```bash
   git push <remote> --delete <remote-branch-name>
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
the remote branch preserved/recoverable. Report each worktree action, local
action, and remote action separately.

Do not run prune merely because branch rows were confirmed or processed. If
prune IDs were separately confirmed, immediately run a new
`git worktree prune --dry-run --verbose` preview and compare every exact
metadata record/path with the complete confirmed set. If any record is added,
removed, changed, unparseable, or not explicitly confirmed, mark prune
`SKIP` because the repository-wide command cannot target the requested subset.
Only an exact match authorizes the non-forced `git worktree prune --verbose`
operation; record its output and one outcome for each confirmed prune action.
Report one outcome row per candidate, per worktree action, and per prune action,
using statuses such as `DELETED`, `SKIP_CHANGED`, `SKIP_UNSAFE`, `SKIP`, or
`FAILED`, with the observed refs, SHAs, commands, and failure reason.

## Script decision

This skill intentionally has no `scripts/plan-cleanup.ts`. The direct Git and
GitHub CLI procedure is reproducible, keeps plan evidence tied to live state,
and makes the per-candidate revalidation visible. Do not add a placeholder or
replace the live checks with cached script output. Add a read-only script only
if a future repeated workflow proves that deterministic collection cannot be
performed safely from these commands alone.
