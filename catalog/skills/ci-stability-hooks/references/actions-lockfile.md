# GitHub Actions Workflow Lockfiles

Use this reference when a repository adopts, reviews, or updates `.github/workflows/actions.lock`, or when deciding between a workflow lockfile and commit-SHA pins in `uses:`.

## What It Does

GitHub Actions workflow dependency lockfiles became generally available on 2026-10-28 for github.com plans and GitHub Enterprise Cloud (including data residency). The lockfile `.github/workflows/actions.lock` records every action a workflow uses, including transitive ones pulled in by other actions, with the exact commit for each reference.

For an onboarded workflow, GitHub resolves each dependency through the lockfile and refuses to run one that has no entry or whose code does not match the recorded commit, before the job runs. That closes the gap left by SHA pins alone: a pinned SHA is not checked at runtime against the action's real repository, and transitive actions are only as pinned as their authors made them.

A lockfile freezes what runs; it does not decide whether an action is safe. Review an action before locking it.

## Which Pinning Style Applies

- Workflow lockfile, preferred when available: `uses:` carries a full version tag such as `actions/checkout@v7.0.1`, the commit lives in `actions.lock`, and no version comment sits next to `uses:`.
- Commit SHA in `uses:` with a version comment: keep this only where the lockfile cannot be used, for example GitHub Enterprise Server (not supported by the tool), or a repository that has not onboarded yet.
- Do not run a SHA-pin checker (for example one that requires `uses: owner/repo@<40-hex>`) on workflows covered by the lockfile; it will reject the tag form. Replace it with the `--verify-local` check below.

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

- `--migrate-local-actions` rewrites same-repository `./` action references to `$/` so the actions they use can be locked (see below).
- `--no-interactive` keeps the run headless.
- The trailing `--verify` asks GitHub whether every locked commit is reachable from its recorded ref. It needs network access and a GitHub login that can read every action repository the workflows reference, including private or internal ones.

Rerun the generate task after adding a workflow or changing any `uses:`.

## What The Workflows Look Like Afterwards

- External actions: `uses: owner/repo@<sha>` becomes `uses: owner/repo@vX.Y.Z`. A partial tag such as `@v4` is narrowed to the full tag unless `--no-narrow` is passed. The commit moves into the lockfile.
- Same-repository composite actions: `uses: ./.github/actions/setup` becomes `uses: $/.github/actions/setup`, in workflows and inside the repository's own action files. A `$/` reference always runs at the workflow's own commit and takes no `@ref`. Without the migration, a local `./` action that uses remote actions is a blocking error, because `./` actions are never followed or locked. If the repository uses self-hosted runners, confirm their runner version supports `$/` inside composite actions before merging.
- Same-repository reusable workflow calls (`jobs.<id>.uses: ./.github/workflows/x.yml`) can stay `./`; the called workflow is locked as its own workflow.
- Version comments such as `# actions/checkout v7.0.1` above or after `uses:` become redundant: the tag and the lockfile carry the version. Delete them in the same change; the generator does not.
- The generator may add a header comment marking the workflow as managed by `gh actions-lock`.

Before merging the migration, compare each lockfile `commit` with the SHA the old `uses:` pinned at the same reference. If they match, the code that runs has not changed.

## CI Check

Add a lightweight job (or a step in an existing lockfile/config sync job) that installs the tool and runs the verify task:

```yaml
- name: Install gh-actions-lock
  env:
    GITHUB_TOKEN: ${{ github.token }} # avoids anonymous GitHub API rate limits during install
  run: mise install gh-actions-lock

- name: Check actions.lock covers workflows
  run: mise run actions-lock:verify
```

It fails when the lockfile is malformed or when a `uses:` has no lockfile entry. Keep this check even though GitHub enforces the lockfile at runtime: GitHub currently ignores a malformed lockfile instead of failing the run ([gh-actions-lock#125](https://github.com/github/gh-actions-lock/issues/125), open as of 2026-11), so CI is the only place that stops one from landing. `--verify-local` is offline and fast, so it also fits a staged `pre-commit` job on `.github/**` per the gate split in `SKILL.md`.

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
