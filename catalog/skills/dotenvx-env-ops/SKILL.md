---
name: dotenvx-env-ops
description: Use when operating dotenvx-managed environment files, encrypted `encrypted:` values, `.env.*` loading, `dotenvx run`, or when dotenvx/mise environment injection may affect CLI tools such as AWS CLI, Terraform, CDK, GitHub CLI, or perman-aws-vault. Trigger for `.env.development`, `.env.staging`, `.env.production`, `.env.dev`, env drift, secret redaction, and commands that need a clean environment instead of decrypted app env.
---

# dotenvx-env-ops

Use this skill to decide whether a command should run inside dotenvx, outside dotenvx, or in a sanitized environment.

## Core Rule

- Run application commands that intentionally need project secrets with `dotenvx run -f <env-file> -- <command>`.
- Run infrastructure/auth/tooling commands outside dotenvx unless the repo explicitly requires decrypted app env.
- If `AWS_*`, `GITHUB_*`, or other tool credentials look like `encrypted:...`, treat the shell as polluted and sanitize before running the tool.
- Never print decrypted secrets. Show only presence, file names, key names, or masked values.

## Workflow

1. Identify the command class.
   - App/runtime: server start, app tests, scripts that read project env.
   - Tooling/auth: `aws`, `terraform`, `cdk`, `gh`, `git`, `mise`, `perman-aws-vault`.
2. Inspect env loading sources before execution.
   - Check relevant `.env*`, `mise.toml`, and task definitions.
   - Look for `encrypted:` values and auto-loading via mise.
3. Choose execution mode.
   - App/runtime: use `dotenvx run -f <file> -- <command>`.
   - Tooling/auth: use a clean env or a direct binary path if shims inject env.
4. Verify with a harmless read-only command first.
   - For AWS, use `sts get-caller-identity`.
   - For dotenvx app env, use a non-secret health/version or dry-run command when available.
5. Report only the command shape, selected env file, and pass/fail signal.

## AWS and perman-aws-vault

When AWS CLI, Terraform, CDK, or perman-aws-vault is involved, also use the `perman-aws-vault` skill for profile/account selection. This skill owns the dotenvx sanitation step before invoking those tools.

Before AWS execution, inspect these names without printing secrets:

```bash
printenv AWS_PROFILE AWS_DEFAULT_PROFILE AWS_REGION AWS_DEFAULT_REGION 2>/dev/null
```

If any selected value is encrypted or inherited from app dotenvx config, run AWS from a clean environment with the profile/region chosen for the task:

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

Prefer the non-shim AWS binary when a `mise` shim or repo task is injecting dotenvx values; `mise which aws` resolves the real binary behind the shim. A concrete worked example (profile, region, incident) is in `references/asta-dotenvx.md`.

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

## Project References

- For ASTA-specific patterns and the AWS dotenvx incident, read `references/asta-dotenvx.md`.

## Guardrails

- Do not source encrypted `.env.*` files directly with shell `source` or `export $(...)`.
- Do not run AWS/GitHub/auth CLIs under app dotenvx env unless the command explicitly requires app secrets.
- Do not commit plain secret files. If a local plain file is needed, ensure the repo already ignores it.
- Do not introduce new env conventions until existing repo docs/tasks have been checked.
