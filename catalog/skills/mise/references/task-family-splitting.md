# Task Family Splitting

Use this reference when a project-local `mise.toml` is growing because it owns multiple operational domains.

## When to Split

Prefer a single root `mise.toml` until one of these is true:

- A task family has a clear owner or operational domain, such as DB, env/dotenvx, secrets, infra, deploy, or tools.
- The root file mixes day-to-day checks with risky operator commands such as production secrets, tunnels, or apply tasks.
- Reviewers must scan many unrelated task definitions to understand a small change.
- The repo already uses `[task_config].includes` successfully.

Do not split only because the file is long. Split by responsibility.

## Root File Responsibilities

Keep these in the root `mise.toml`:

- `[settings]`, root `[env]`, and root `[tools]`
- primary app lifecycle tasks such as `dev`, `build`, `start`
- common check, lint, format, test, and CI aggregators
- `[task_config].includes`

The root file should still explain the normal developer entrypoints without forcing readers into include files.

## Include File Responsibilities

Use `mise/<family>.toml` or another repo-established include directory.

Good candidates:

- `mise/db.toml`: migrations, schema push, seed, DB docs, DB studio
- `mise/env.toml` or `mise/dotenvx.toml`: encrypt/decrypt, print to stdout, get a single key
- `mise/secrets.toml`: SSM, Secrets Manager, production env sync, operator-only secret checks
- `mise/infra.toml` or `mise/terraform.toml`: Terraform, Pulumi, CDK, local cloud smoke tasks
- `mise/deploy.toml`: release, rollout, production apply, environment-specific deploy tasks
- `mise/tools.toml`: tool smoke checks or installer wrappers when they are tasks, not `[tools]` declarations

Keep `[tools]` declarations in the root or environment config unless the repo already has a different source of truth. Do not hide tool versions inside task files.

## Include File Syntax

Root file:

```toml
[task_config]
includes = [
  "mise/db.toml",
  "mise/env.toml",
  "mise/terraform.toml",
]
```

Included task file:

```toml
["db:push"]
description = "Push schema to the development database"
run = "pnpm db:push"

["db:init"]
description = "Push schema and seed development data"
run = [{ task = "db:push" }, { task = "db:seed" }]
```

Use the include-file table form `["task:name"]`, not root-style `[tasks."task:name"]`, unless the repo has verified another shape.

## dotenvx Tasks

Keep destructive and non-destructive dotenvx operations separate.

```toml
["env:decrypt"]
description = "Decrypt environment files in place"
run = "pnpm dotenvx decrypt -f .env.development"

["env:print:development"]
description = "Print decrypted development environment to stdout"
run = "pnpm dotenvx decrypt -f .env.development --stdout"

["env:get:development"]
description = "Print one development environment value"
usage = 'arg "<key>" help="Environment variable name to print"'
run = 'pnpm dotenvx get "${usage_key?}" -f .env.development'
```

Prefer `decrypt --stdout` or `get <KEY>` when the user only wants to inspect values. Avoid adding print tasks to CI or shared logs because they can expose secrets.

If using mise task arguments, prefer `usage` variables over shell `"$@"` when the command has positional parsing. Otherwise mise may append task arguments after the run string and the underlying CLI can misinterpret them.

## Verification

After splitting:

- Run `mise tasks ls` and confirm every moved task still appears.
- Run `mise task deps <entrypoint>` for affected entrypoints such as `check`, `ci`, `deploy`, or `release`.
- Use `rg` to confirm moved root task definitions disappeared from root and reappeared in exactly one include file.
- Do not execute DB, secret, deploy, or production tasks just to prove registration unless the user explicitly requested it.
- Review diff for behavior preservation: task names, descriptions, and commands should remain unchanged unless the refactor intentionally changes behavior.
