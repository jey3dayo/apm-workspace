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

## Delegate planning to a cheap subagent

Planning has no step that deletes a branch or worktree and fails closed (the
only write command it runs is `git fetch --prune`), so hand it to a subagent on a cheap
model (Claude Code: the Agent tool with `model: haiku`). Pass it the absolute
checkout path and this skill's path. The subagent inherits the parent's
working directory, not the checkout's, so it runs every Git command as
`git -C <checkout> …` and never `cd`s. It runs "Resolve the repository and
live context" through "Present the Markdown plan" and returns the proposed,
exclusion, and prune tables with their evidence objects, plus the output of
`git -C <checkout> rev-parse --path-format=absolute --show-toplevel --git-common-dir`.
The parent runs that command itself and discards a plan whose output differs.
The subagent is plan-only: it never
asks the user and never runs a deletion or prune. The parent session shows the
returned plan, asks one y/n when the proposed table has rows, and runs "Revalidate and
execute confirmed rows" itself; that live revalidation is what catches a wrong
plan row. Keep `model:` out of this skill's frontmatter: a forked skill cannot
reach the user, and the confirmation boundary must stay with the parent.

## Safety contract

- Treat every invocation as `plan-only` until the user answers y to the plan
  just shown. One y/n covers every row in the proposed table, which holds only
  rows that passed every gate; the user does not restate row IDs, refs, or
  SHAs, and the skill never asks per proposed row. “Clean up branches” alone is not that
  answer, because it comes before the plan exists. A y never covers the
  exclusion table or the prune table. A y given to a stale plan is invalid;
  make a new plan.
- The automatic candidate set is a local branch with one unambiguous upstream
  branch on a resolved remote. A remote-only branch is never an automatic
  candidate.
- The parsed base repository owner, same-repository PR head repository
  identity, base repository, local branch SHA, and every same-repository
  matching PR head SHA must be known and agree. The upstream remote SHA must
  agree as well while the upstream branch still exists; an upstream branch
  already deleted from the remote is `remote-absent` and gates on the
  remaining evidence. External rows
  are recorded separately and are never evidence for deletion. The
  authenticated GitHub actor must also be known, but is recorded separately
  from the base repository owner; do not require a human actor to be the owner
  of an organization-owned repository. Unknown, divergent, or ambiguous state
  in the gating set is `SKIP`.
- Exclude the default branch, current branch, every protected branch, and any
  branch whose related worktree is the main worktree, current worktree,
  locked, dirty, unreadable, or otherwise ambiguous.
- A dirty worktree includes any tracked or untracked file reported by
  `git -C <worktree-path> status --porcelain=v1 --untracked-files=all`.
- Partition PRs whose head branch matches the candidate into same-repository
  rows and fork/other-repository rows. Record the count and details of the
  excluded fork/other-repository rows, but do not put them in the matching set
  that gates deletion. Require at least one same-repository row; every such
  row must be `MERGED`, non-draft, and SHA-equal. A same-repository `OPEN`,
  draft, closed-but-unmerged, or otherwise unresolved row excludes the
  candidate. Fork/other-repository rows neither veto the candidate nor satisfy
  the at-least-one requirement.
- Only clean linked worktrees can be removed, and only with the exact native,
  non-forced command `git -C <checkout> worktree remove -- <exact-absolute-path>` after
  validating the installed Git syntax. If that Git does not accept `--`, pass
  the exact absolute path as its own argv element in the non-forced form
  `git -C <checkout> worktree remove <exact-absolute-path>`; never turn the path into a shell
  fragment. Do not use a `git wt` delete operation: it can also delete the
  branch and run `wt.deletehook`. Never pass a force flag to a worktree removal
  command.
- Process a confirmed row in this order: remove its safe linked worktrees,
  delete the local branch with `git branch -d` (or the narrow `-D` fallback
  described below), then delete the remote branch. On a `remote-present` row,
  keep the remote/upstream ref until local deletion completes: it supplies
  `git branch -d` with its mergedness evidence, and a later remote-deletion
  failure leaves a recoverable remote branch. A `remote-absent` row has no
  such ref and no remote step at all — only worktrees and the local branch are
  in scope, and nothing about it is recoverable from the remote. Use `git branch -D` only for the narrow squash or
  rebase case after the same exact SHA and merged-PR evidence has passed live
  revalidation and the row was in the plan the user confirmed with y.

## Resolve the repository and live context

Every Git command in this skill, in planning and in execution, takes the
checkout explicitly as `git -C <checkout> …`; never rely on the shell's working
directory and never `cd` into the checkout. No `gh` command may infer the
repository from the working directory. Resolve values; do not assume `main`,
`master`, or `origin`.

1. Confirm that the path is a Git checkout and record its identity:
   `git -C <checkout> rev-parse --path-format=absolute --show-toplevel --git-common-dir`.
   Choose the base remote: the one remote whose `remote.<name>.gh-resolved` is
   `base` (written by `gh repo set-default`; read it with
   `git -C <checkout> config --get-regexp '^remote\..*\.gh-resolved$'`);
   otherwise the only configured remote; otherwise, if every remote's fetch URL
   resolves (with `gh repo view <fetch-url> --json nameWithOwner`) to the same
   repository, any of them; a failed or empty resolution counts as a mismatch.
   Anything else makes automatic cleanup unavailable; suggest running
   `gh repo set-default` in that checkout instead of picking a remote by name. Resolve the GitHub repository and default branch from that
   remote's fetch URL, not from a conventional branch name:

   ```bash
   gh repo view "$(git -C <checkout> remote get-url <base-remote>)" --json nameWithOwner,defaultBranchRef --jq '[.nameWithOwner, .defaultBranchRef.name] | @tsv'
   ```

   Record `nameWithOwner`, never the URL, in evidence: a remote URL can embed
   credentials. Failure to resolve either value makes automatic cleanup
   unavailable. A branch that tracks a fork remote never maps to the base
   repository and ends as `SKIP`.

2. Resolve the authenticated actor with `gh api user --jq .login`. Record it
   as the actor, and treat an unavailable login as `SKIP`; do not infer actor
   identity from Git config or a remote URL. This actor value is not the base
   repository owner check below.

3. Resolve the current branch with
   `git -C <checkout> symbolic-ref --quiet --short HEAD`. A detached HEAD has no automatic
   cleanup candidates. Record the exact current worktree path and common Git
   directory as additional identity checks.

4. Enumerate configured remotes with `git -C <checkout> remote` and inspect each fetch URL
   using `git -C <checkout> remote get-url <remote>`. For a branch, use its configured
   upstream metadata rather than choosing a name by convention:

   ```bash
   git -C <checkout> for-each-ref --format='%(refname:short)%09%(upstream)%09%(upstream:remotename)%09%(upstream:remoteref)%09%(objectname)' refs/heads
   ```

   Select a remote only when its fetch URL, resolved with
   `gh repo view <fetch-url> --json nameWithOwner` rather than by parsing the URL,
   resolves to the GitHub repository returned above and the branch's upstream
   metadata names that remote. If a
   remote cannot be mapped, or a branch has no single upstream, mark that
   branch `SKIP`. A remote can be selected per candidate; there is no implicit
   `origin`. `git push` sends to every push URL of the remote, and those can
   differ from the fetch URL: list them with
   `git -C <checkout> remote get-url --push --all <remote>`. Require exactly
   one push URL and resolve it with `gh repo view <push-url> --json
nameWithOwner`; zero or several URLs, a failed resolution, or a different
   repository makes that remote's `remote-present` candidates `SKIP_UNSAFE`
   (a partial push to several URLs could not be reported as `PRESERVED`).

5. Parse the base repository owner from the resolved `nameWithOwner`: require
   exactly one `/` separating two non-empty segments, using the first as the
   owner and the second as the repository name. If it cannot be parsed that
   way, mark the repository `SKIP`. Resolve protected branch names from GitHub.
   If this read fails, do not delete any branch because protected-state is
   unknown:

   ```bash
   gh api --paginate "repos/<nameWithOwner>/branches?protected=true&per_page=100" --jq '.[].name'
   ```

6. Read registered worktrees with `git -C <checkout> worktree list --porcelain`, then use
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

Candidate construction lives in [references/candidate-construction.md](references/candidate-construction.md). The planning phase reads that file together with this one: it defines the upstream validation, the single `ls-remote` and repository-wide PR queries, the candidate-level rules check, worktree exclusion, and the evidence object each candidate and exclusion must carry. Do not construct candidates from this summary alone.

## Present the Markdown plan

The plan format lives in [references/plan-format.md](references/plan-format.md). The planning phase reads that file together with this one: it defines the proposed, exclusion, and prune tables, the `remote-absent` presentation rules, and the single y/n question that ends the planning phase. Do not present a plan from this summary alone.

## Revalidate and execute confirmed rows

Execution lives in [references/execution-revalidation.md](references/execution-revalidation.md). Only the parent session reads that file, and only after the user answers y to the plan just shown: it defines the per-row live revalidation gate, the worktree → local → remote execution order, and the per-action outcome reporting. Its gate reuses two planning definitions (the same-repository partition and the all-page rules query), so the parent also reads those sections of [references/candidate-construction.md](references/candidate-construction.md) at that point. The planning subagent never reads or runs this phase.

## Script decision

This skill intentionally has no `scripts/plan-cleanup.ts`. The direct Git and
GitHub CLI procedure is reproducible, keeps plan evidence tied to live state,
and makes the per-candidate revalidation visible. Do not add a placeholder or
replace the live checks with cached script output. Add a read-only script only
if a future repeated workflow proves that deterministic collection cannot be
performed safely from these commands alone.
