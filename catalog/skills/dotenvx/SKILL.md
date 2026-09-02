---
name: dotenvx
description: Use when operating dotenvx-managed environment files, `encrypted:` values, `.env.*` loading, `dotenvx run`, env drift, secret redaction, or when dotenvx/mise environment injection may pollute CLI tools such as AWS CLI, Terraform, CDK, GitHub CLI, or perman-aws-vault. This skill leads dotenvx key rotation end-to-end (`dotenvx rotate`, `.env.keys` replacement, storing the new private key in 1Password); delegate the 1Password item update step to `1password`.
---

# dotenvx

Decide whether a command runs inside dotenvx, outside dotenvx, or in a sanitized clean environment.

## Core Rule

- App/runtime commands that intentionally need project secrets run inside dotenvx: `dotenvx run -f <env-file> -- <command>`.
- Infrastructure/auth/tooling commands (`aws`, `terraform`, `cdk`, `gh`, `git`, `mise`, `perman-aws-vault`) run outside dotenvx unless the repo explicitly requires decrypted app env.
- A shell where `AWS_*`, `GITHUB_*`, or other tool credentials look like `encrypted:...` is polluted: sanitize to a clean env before running the tool.
- Show only presence, file names, key names, or masked values — never a decrypted secret.

## Workflow

1. Classify the command: app/runtime (server start, app tests, scripts reading project env) or tooling/auth.
2. Inspect env loading sources: relevant `.env*`, `mise.toml`, task definitions, `encrypted:` values, mise auto-loading.
3. Apply the Core Rule. For a polluted shell, use a clean env or the non-shim binary path.
4. Verify with a harmless read-only command first: `sts get-caller-identity` for AWS; a non-secret health/version or dry-run command for dotenvx app env.
5. Report only the command shape, selected env file, and pass/fail signal.

## AWS and perman-aws-vault

When AWS CLI, Terraform, CDK, or perman-aws-vault is involved, also use the `perman-aws-vault` skill for profile/account selection. This skill owns the sanitation step before invoking those tools.

Before AWS execution, inspect these names without printing secrets:

```bash
printenv AWS_PROFILE AWS_DEFAULT_PROFILE AWS_REGION AWS_DEFAULT_REGION 2>/dev/null
```

If any selected value is encrypted or inherited from app dotenvx config, the shell is polluted — run AWS from a clean environment with the profile/region chosen for the task:

```bash
AWS_BIN="$(mise which aws 2>/dev/null || command -v aws)"
env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE \
  -u AWS_REGION -u AWS_DEFAULT_REGION \
  -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
  AWS_PROFILE=<profile> \
  AWS_REGION=<region> \
  AWS_DEFAULT_REGION=<region> \
  "$AWS_BIN" sts get-caller-identity
```

Prefer the non-shim AWS binary when a `mise` shim or repo task injects dotenvx values; `mise which aws` resolves the real binary behind the shim. A concrete worked example (profile, region, incident) is in `references/asta-dotenvx.md`.

## dotenvx Recipes

Run a command with decrypted app env:

```bash
dotenvx run -f .env.development -- pnpm dev
dotenvx run -f .env.staging -- pnpm test
```

When an encrypted `.env` has a separate `.env.keys` file, pass the key file before
the env file for mutation and verification commands:

```bash
dotenvx set SLACK_BOT_TOKEN "$slack_token" -fk .env.keys -f .env
dotenvx get SLACK_BOT_TOKEN -fk .env.keys -f .env >/dev/null
```

If `dotenvx set` fails with `MISPAIRED_PRIVATE_KEY`, do not assume the stored
secrets are corrupt. First verify whether `.env`'s `DOTENV_PUBLIC_KEY` matches
the public key derived from `.env.keys`, while printing only short prefixes:

```bash
env_public_prefix=$(
  sed -n 's/^DOTENV_PUBLIC_KEY="\{0,1\}\([0-9a-f]\{8\}\).*/\1/p' .env
)
derived_public_prefix=$(
  dotenvx keypair -fk .env.keys --format json |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("DOTENV_PUBLIC_KEY","")[:8])'
)
printf 'env_public_prefix=%s\n' "$env_public_prefix"
printf 'derived_public_prefix=%s\n' "$derived_public_prefix"
```

If the prefixes match, retry with `-fk .env.keys -f .env` ordering before
rotating keys or replacing `.env.keys`.

Check which keys exist without exposing values (`-o` prints only the matched key, never the value):

```bash
rg -n -o '^[A-Z0-9_]+=' .env .env.* 2>/dev/null
```

List encrypted keys without exposing values:

```bash
rg -n -o '^[A-Z0-9_]+=encrypted:' .env .env.* 2>/dev/null
```

## Guardrails

- Load encrypted `.env.*` only through dotenvx commands, never shell `source` or `export $(...)`.
- Keep plain secret files out of commits; a needed local plain file must already be repo-ignored.
- Follow existing repo env docs/tasks before introducing a new env convention.
- Decryption failure only inside a git worktree (key not found, `MISPAIRED_PRIVATE_KEY` while the main checkout works) usually means the gitignored `.env.keys` was never copied there. Fix it via the `git-worktree` skill: `wt.copy` config for `git wt`, or `scripts/copy-env-files.sh` for worktrees created by any other path.
