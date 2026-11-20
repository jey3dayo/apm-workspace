# Candidate construction (git-branch-cleanup reference)

This reference is part of `git-branch-cleanup`. Read it together with `SKILL.md` when constructing the candidate set in the planning phase. The safety contract in `SKILL.md` always applies.

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
planning set (`git -C <checkout> fetch --prune <remote>`). This synchronization is allowed in plan-only mode; it does not
authorize branch or worktree deletion. A failed fetch leaves that remote's
candidates in `SKIP`.

The planning pass makes exactly one remote-head query per resolved remote, with
no branch argument:

```bash
git -C <checkout> ls-remote --heads <resolved-remote>
```

Parse each complete successful result client-side. For a validated full
`refs/heads/<remote-branch-name>`, require at most one matching row; multiple
or malformed rows are `SKIP`. Do not issue another planning `ls-remote` for
that remote. Resolve each local SHA with `git -C <checkout> rev-parse <local-ref>`.

Exactly one row supplies the authoritative remote SHA, which must equal the
local SHA; a divergent SHA is `SKIP`. Zero rows means the upstream branch is
already gone from the remote, which is the normal end state in a repository
that deletes head branches on merge. Classify that as `remote-absent` rather
than `SKIP`: the candidate proceeds on agreement between the local SHA and the
same-repository merged PR head SHA, and its plan carries no remote-deletion
command because nothing is left to delete. A `remote-absent` candidate still
needs every other gate, including at least one same-repository `MERGED`,
non-draft PR whose `headRefOid` equals the local SHA.

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
   `headRefOid`, and a `headRefOid` equal to the local SHA. For a
   `remote-present` row it must equal the authoritative remote SHA as well; a
   `remote-absent` row has no remote SHA and never has one substituted for it.
   If the CLI cannot enumerate all repository rows, classify the candidate as
   `SKIP` rather than relying on a partial list. Same-repository
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
   gh api --paginate --slurp "repos/<nameWithOwner>/rules/branches/<URL-encoded-branch>"
   ```

   This is the **all-page rules query**; every later step that re-runs the
   rules check runs this exact form again rather than a bare `gh api`. The
   endpoint paginates, so a rule that forbids deletion can sit past the first
   page. Bare `--paginate` prints each page as its own JSON value, so never
   parse that stream as one array; `--slurp` wraps the pages in an outer array.
   Require the command itself to exit zero — a non-zero exit discards whatever
   reached stdout, and the exit status of a trailing `jq` is not the exit
   status of the query. Then require the outer value to be an array, require
   every page inside it to be an array, and flatten one level to get the rule
   list. Anything else is `SKIP`.

   Every element must have a non-empty `type` plus ruleset identity such as
   `ruleset_id` and `ruleset_source`. The branch-rules endpoint returns applied
   rule objects rather than ruleset-level `enforcement` metadata, so do not
   require an `enforcement` field. If any returned rule lacks that identity,
   classify the candidate as `SKIP`.

   Judge protection by rule `type`, never by array length, and evaluate only
   the rules the API returned for this candidate's own name. `deletion`
   restricts deleting a matching ref and is protection at any scope or
   pattern; `non_fast_forward` restricts force-pushing a matching ref. A
   candidate carrying either is `protected`. Let a candidate proceed only when
   every remaining type appears in the confirmed-unrelated table below, or is
   one whose meaning you confirmed against primary documentation in this run
   and recorded as evidence. A type whose meaning is unconfirmed is
   `SKIP_UNSAFE`, matching the rule that unknown state in the gating set never
   passes; do not let an unrecognized type through because it is not on the
   forbidden list.

   | type                    | meaning                             | source                                        |
   | ----------------------- | ----------------------------------- | --------------------------------------------- |
   | `max_file_size`         | limits the size of a pushed file    | <https://docs.github.com/en/rest/repos/rules> |
   | `file_path_restriction` | limits which paths a push may touch | <https://docs.github.com/en/rest/repos/rules> |

   Array length is not the test because a repository ruleset can apply
   content-level push rules to a wide ref pattern, and treating a non-empty
   array as protection would mark every branch in such a repository protected.
   Do not try to separate the two by querying a name that does not exist: the
   endpoint returns the rules that would apply to _that_ name, so a ruleset
   scoped to all refs returns `deletion` for it as well, and a name matching a
   narrower pattern says nothing about the repository as a whole. Such a query
   is diagnostic only and never relaxes a safety decision.
   Combine this candidate-level result with the required protected baseline:
   legacy protection from `branches?protected=true` and ruleset-only
   protection both fail closed. A branch in either set is protected; do not
   delete it. URL-encode slashes and other reserved characters in the branch
   name exactly once.

4. For every related worktree, exclude the candidate if it is the main or
   current worktree, has a `locked` or `prunable` marker, has any tracked or
   untracked change, or has a process using its path (`lsof +D <path>` lists a
   working directory or open file under it; a failed query is `SKIP_UNSAFE`).
   `lsof` may not see a process inside a container's bind mount, so ask the
   user before removing a worktree that runs a dev stack such as `tilt` or
   `docker compose`. Require every related worktree to be clean and safe before
   proposing that candidate; never select only the safe subset of an unsafe
   branch's worktrees.

Before presenting the plan, preview stale worktree metadata without changing
anything:

```bash
git -C <checkout> worktree prune --dry-run --verbose
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
