# GitHub Actions Workflow Lockfiles

Use this reference when a repository adopts, reviews, or updates `.github/workflows/actions.lock`, or when deciding between a workflow lockfile and commit-SHA pins in `uses:`.

## What It Does

GitHub Actions workflow dependency lockfiles became generally available on 2026-10-28 for github.com plans and GitHub Enterprise Cloud (including data residency). The lockfile `.github/workflows/actions.lock` records every action a workflow uses, including transitive ones pulled in by other actions, with the exact commit for each reference.

For an onboarded workflow, GitHub resolves each dependency through the lockfile and refuses to run one that has no entry or whose code does not match the recorded commit, before the job runs. That closes the gap left by SHA pins alone: a pinned SHA is not checked at runtime against the action's real repository, and transitive actions are only as pinned as their authors made them.

A lockfile freezes what runs; it does not decide whether an action is safe. Review an action before locking it.

## Which Pinning Style Applies

Decide per workflow and per reference type, not per repository:

- Action references in an onboarded workflow (a workflow listed in `actions.lock`): prefer a full version tag such as `actions/checkout@v7.0.1`, with the commit in the lockfile and no version comment next to `uses:`. A commit SHA in `uses:` is still valid under a lockfile; keep it when no release tag points at that commit or when the repo deliberately keeps SHAs.
- Commit SHA in `uses:` with a version comment: keep this where the lockfile does not reach. That covers workflows not onboarded yet, reusable workflows called from another repository (`jobs.<id>.uses: owner/repo/.github/workflows/x.yml@ref`, which the tool does not lock), and GitHub Enterprise Server, which the tool does not support.
- A SHA-pin checker (one that requires `owner/repo@<40-hex>`) rejects the tag form, so scope it away from action references in onboarded workflows and let the `--verify-local` check below cover those. Keep it for everything in the previous bullet; dropping it repo-wide leaves those references unchecked.

## Install The Generator

The generator is `gh-actions-lock`, GitHub's official tool. Pin an exact version through mise like any other repo tool:

```toml
[tools]
gh-actions-lock = { version = "0.4.0", bin = "gh-actions-lock" }

[tool_alias]
gh-actions-lock = "github:github/gh-actions-lock"
```

The release assets are bare platform names (`darwin-arm64`, `linux-amd64`, ...), so `bin` gives the installed binary a stable name. Without mise, `gh extension install github/gh-actions-lock --pin v0.4.0` installs the same tool as `gh actions-lock`. `gh-actions-lock --help` is authoritative for flags.

## Generate Through One Task

Never edit `actions.lock` by hand. Expose generation and verification as repo tasks (mise tasks shown; a Makefile target works the same way):

```toml
[tasks."actions-lock:generate"]
description = "Regenerate .github/workflows/actions.lock and verify it upstream"
run = [
  "gh-actions-lock --migrate-local-actions --no-interactive",
  "gh-actions-lock --verify",
]

[tasks."actions-lock:verify"]
description = "Offline check: every uses: has a lockfile entry and the lockfile parses"
run = "gh-actions-lock --verify-local"
```

- `--migrate-local-actions` rewrites every same-repository `./` action reference to `$/` so the actions they use can be locked. Check that this is safe first (see below).
- `--no-interactive` keeps the run headless.
- The trailing `--verify` asks GitHub whether every locked commit is reachable from its recorded ref. It needs network access and a GitHub login that can read every action repository the workflows reference, including private or internal ones.

Rerun the generate task after adding a workflow or changing any `uses:`.

## What The Workflows Look Like Afterwards

- External actions: a SHA ref that matches a release tag is typically rewritten to that full tag (`uses: owner/repo@vX.Y.Z`), and the commit moves into the lockfile. A SHA with no matching tag stays as written and is still locked. A newly pinned partial tag such as `@v4` is narrowed to the highest matching full semver tag unless `--no-narrow` is passed; branch names are never narrowed.
- Same-repository composite actions: `uses: ./.github/actions/setup` becomes `uses: $/.github/actions/setup`, in workflows and inside the repository's own action files. A `$/` reference always runs at the workflow's own commit and takes no `@ref`. Without the migration, a local `./` action that uses remote actions is a blocking error, because `./` actions are never followed or locked. If the repository uses self-hosted runners, confirm their runner version supports `$/` inside composite actions before merging.
- `./` and `$/` are not always the same code. `./` reads whatever sits in the job's workspace at that step, so it differs from the workflow's commit when a job checks out another ref or repository into the workspace path, or when an earlier step generates or edits the action. Before migrating, look for those jobs. Keep `./` for any reference that depends on that behavior: replace `--migrate-local-actions` with `--ignore-local-actions` in the generate task, rewrite the safe references to `$/` by hand, and accept that the remote actions used by the remaining `./` actions are not locked.
- Same-repository reusable workflow calls (`jobs.<id>.uses: ./.github/workflows/x.yml`) can stay `./`; the called workflow is locked as its own workflow.
- Version comments such as `# actions/checkout v7.0.1` above or after `uses:` become redundant: the tag and the lockfile carry the version. Delete them in the same change; the generator does not.

Before merging the migration, compare each lockfile `commit` with the SHA the old `uses:` pinned at the same reference. If they match, the code that runs has not changed.

## CI Check

Add these steps to a job that already checks out the repository and sets up mise (an existing lockfile or config sync job fits; mise itself can be set up without installing every tool). A new job needs its own checkout and mise setup steps first.

```yaml
- name: Install gh-actions-lock
  env:
    GITHUB_TOKEN: ${{ github.token }} # avoids anonymous GitHub API rate limits during install
  run: mise install gh-actions-lock

- name: Check actions.lock covers workflows
  run: mise run actions-lock:verify
```

It fails when the lockfile is malformed or when a `uses:` has no lockfile entry. Keep this check even though GitHub enforces the lockfile at runtime: GitHub currently ignores a malformed lockfile instead of failing the run ([gh-actions-lock#125](https://github.com/github/gh-actions-lock/issues/125), open as of 2026-11), so CI is the only place that stops one from landing. `--verify-local` is offline and fast, so it also fits a `pre-commit` job on `.github/**` per the gate split in `SKILL.md`. It reads the working tree, not the staged snapshot, so with a partially staged change it can pass on content that is not being committed; CI stays the authoritative check.

### `--verify-local` vs `--verify` in CI

- Use `--verify` in CI when every locked action is public or readable with the job's `GITHUB_TOKEN`. It re-checks provenance online and is the stronger check; GitHub's own template does this.
- Use `--verify-local` in CI when the workflows use private or internal actions from another repository or organization. The job's `GITHUB_TOKEN` is scoped to the current repository, so `--verify` cannot read those action repositories and fails. Provisioning a broader token as a secret only for this check usually costs more than it adds, because the generate task already ran `--verify` with a developer login and the runner checks provenance again at job start.

`--verify-local` is a coverage check, not a provenance check. It does not notice a lockfile edit that moves a ref back to an older commit in its history. Reading the lockfile diff in review is what covers that.

## Rules

- Bump a `uses:` tag only to a release published at least 7 days earlier, the same cooldown idea as for other dependencies. Then run the generate task and review the diff.
- Review `actions.lock` diffs like code. Do not mark the lockfile as generated or ignored in review tooling (`linguist-generated` in `.gitattributes`, review-bot ignore lists, or generated-path lists that collapse or skip files), because review is the control for the gap `--verify-local` leaves.
- Never pass `--accept-moved` in automation; find out why a locked commit moved first.
- Dependabot version updates for onboarded workflows regenerate the matching lockfile entry in the same pull request.
- Enforcing lockfiles for every workflow (the "Require lockfile" policy) is an administrator setting; decide it separately after adoption.
- Known limits: cross-repository reusable workflows are not locked, container images are not locked (pin them by `@sha256:` digest), and GitHub Enterprise Server is not supported.

## Sources

- GitHub Changelog, 2026-10-28: <https://github.blog/changelog/2026-10-28-github-actions-workflow-lockfiles-are-generally-available/>
- `gh-actions-lock` README, modes and limitations: <https://github.com/github/gh-actions-lock>
- Walkthrough of the preview (Japanese): <https://qiita.com/access3151fq/items/70a93f08bffd9c5f09a5>
