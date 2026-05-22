---
name: perman-aws-vault
description: Use when AWS CLI/profile/configuration, Terraform/CDK AWS credentials, PERMAN Federation SAML auth, ~/.aws files, credential_process/keychain, or nearshore/CAAD/CA-Nic AWS environments are involved. Enforces AWS_PROFILE discovery first from .env/mise/current shell, print before select authentication checks, no install attempts for perman-aws-vault, stop if profile is unknown, safe ~/.aws/config initialization, and production approval gates.
---

# perman-aws-vault

## Overview

PERMAN Federation SAML認証を通じてAWS一時的セキュリティ認証情報を取得し、keychainなどのキーストアで安全に管理するツール。AWS CLIの`credential_process`と統合することで、AWS操作時の認証を自動化する。

このスキルは、AWS_PROFILEの発見、perman-aws-vaultの既存バイナリ探索、認証状態の確認、AWS/Terraform/CDK実行の安全な進め方を決めるために使う。profileは環境名から推測せず、リポジトリや現在のshellの設定から発見する。

## How to Use This Skill

### Execution Mode

Choose the smallest safe execution mode:

- Direct execution / direct response: Use for simple, one-off commands where the profile is already known, especially read-only operations.
- Subagent delegation: Use when the runtime provides subagents and the task is multi-step, needs project-context inspection, may affect infrastructure, or mixes AWS CLI/Terraform/CDK work.
- Stop and ask/setup: Use when the AWS environment, profile, conflicting `~/.aws/config` state, Terraform workspace/backend/var-file, or production approval is unclear.

When delegating, pass the subagent the user request, working directory, detected environment clues, selected profile if known, and the safety rules from this skill. The subagent must:

1. Discover AWS_PROFILE from repository/runtime sources before any environment keyword inference
2. Stop if AWS_PROFILE is missing, polluted, or ambiguous
3. Find an existing perman-aws-vault binary without installing it
4. Try `perman-aws-vault print -p <config-path>` before `select`
5. Execute only commands that are safe for the confirmed profile, environment, and approval state

### When to Launch Subagent

Launch a subagent for:

- AWS CLI command execution (S3, EC2, Lambda, RDS, etc.)
- Terraform operations requiring AWS credentials
- Multi-step AWS workflows requiring authentication management
- Operations where environment context needs to be inferred
- Any production/CAAD change or destructive operation

### Direct Command Execution

For simple, one-off commands where the profile is already known, execute directly without launching a subagent:

```bash
aws s3 ls --profile <discovered-profile>
aws sts get-caller-identity --profile <discovered-profile> --region ap-northeast-1
```

Before direct execution, still apply the preflight checks below.

### Preflight and Safety Gates

Before running AWS CLI, Terraform, CDK, or a command plan that assumes credentials:

1. Discover AWS_PROFILE first. Search `.env*`, `mise.toml`, `mise.local.toml`, Terraform execution directories, and the current shell value (`echo $AWS_PROFILE`). Do not print AWS access keys, session tokens, or other secret values while searching.
2. Stop unless AWS_PROFILE is exactly one usable value. Treat missing values, multiple different values, empty values, and polluted values such as `encrypted:...` as blocked preconditions. Do not choose a profile from `production`, `CAAD`, or other keywords alone.
3. Find an existing `perman-aws-vault` binary. Check `command -v perman-aws-vault`, `mise which perman-aws-vault`, `/opt/homebrew/bin/perman-aws-vault`, `/usr/local/bin/perman-aws-vault`, and `~/.mise/shims/perman-aws-vault`. Codex must not run `brew install`, `scoop install`, or any other install command for this tool. If no binary is found, stop and report the searched locations.
4. Check `~/.aws/config`. If the discovered profile is a known profile from this skill and is missing, initialize the profile stanza before AWS execution. If the profile exists but has a missing or conflicting `credential_process`, stop and ask before modifying it.
5. Check the profile config path, normally `~/.config/perman-aws-vault/<AWS_PROFILE>`, and then try `perman-aws-vault print -p <config-path>`. Use the discovered binary path when PATH may differ under `credential_process`.
6. Run `perman-aws-vault select` only when `print -p` shows authentication/setup is required. During `select`, verify the authentication message and then place the generated `.perman-aws-vault` under the target profile config directory.
7. Prefer `credential_process` with `AWS_PROFILE` for Terraform/CDK and `--profile` for simple AWS CLI inspection only when that matches the final command. STS or plan checks must use the same profile injection method as the real command.
8. Never expose or request secret values. Ask the user to complete authentication/setup locally when user approval or secret input is required.
9. Require explicit confirmation before production/CAAD changes. Read-only CAAD inspection can proceed after profile/config checks, but production deploy/apply/delete/update operations must stop for confirmation. Words such as "見たい", "確認したい", or "あとで適用も" are not approval; ask for an explicit `y/n` or equivalent confirmation before showing or running an apply/deploy command.
10. For Terraform/CDK, confirm the project-specific workspace, backend, var-file, stack, or context before apply/deploy. If unknown, provide only non-destructive discovery or plan commands with placeholders, list the missing selectors, and ask for the selectors before producing a concrete apply/deploy command.

When a required input is missing, report it as **Blocked preconditions** instead of treating it as permission to guess:

- Missing, ambiguous, or polluted AWS_PROFILE: stop and report the sources checked. Do not infer from environment keywords.
- Missing `perman-aws-vault` binary: stop after reporting searched locations. Do not install it.
- Missing AWS config for a discovered known profile: initialize `~/.aws/config` safely, then continue to `print -p` authentication checks.
- Unknown or conflicting AWS profile/config: stop before AWS execution and show the needed `credential_process` snippet.
- Missing Terraform/CDK selector: list the missing workspace/backend/var-file/stack/context/app path and stay on discovery/plan.
- Missing production approval: ask for explicit approval after the plan/diff target is fixed.

## Subagent Workflow

### AWS_PROFILE Discovery

Determine AWS_PROFILE from concrete repository/runtime sources, not from environment labels.

Discovery sources, in order:

1. Explicit `AWS_PROFILE=<value>` in user request or command snippet
2. Current shell: `echo $AWS_PROFILE`
3. Repository env files: `.env`, `.env.*`, `.envrc`, and Terraform/CDK env files in the execution directory
4. `mise.toml` and `mise.local.toml`
5. Existing `~/.aws/config` only as a consistency check for the discovered name, not as a source for choosing among many profiles

Use `rg` or equivalent targeted search. Search for `AWS_PROFILE`, but do not dump full `.env` files because they may contain secrets. `AWS_PROFILE` itself is not a secret.

Stop when:

- No AWS_PROFILE value is found
- Multiple different AWS_PROFILE values are found and the target execution context does not make one unique
- The value is empty, templated, or polluted, such as `encrypted:...`
- Only generic words like `production`, `staging`, or `CAAD` are available

When stopped, report the checked sources and the exact candidate profile names, if any.

### Profile Selection Strategy

Use the discovered AWS_PROFILE as the selected profile. Keyword-based mapping is fallback context only and must not override discovery.

Fallback context:

- Nearshore/development context often uses `aws-caad-ndev-admin`
- CAAD production context may use `aws-caad-admin-role`
- CA-Nic production developer-role context may use `CA-Nic-prd`

If fallback context suggests a profile but AWS_PROFILE was not discovered, stop and ask for the correct profile rather than running AWS commands.

Known profile details are maintained in `references/profile-catalog.md`. Use that table for safe `~/.aws/config` auto-init targets, config paths, region, and alias wording. Do not use the table to infer a profile when `AWS_PROFILE` was not discovered.

### AWS CLI Config Initialization

This skill owns safe initialization of `~/.aws/config` for known perman-aws-vault profiles.

Known profiles and credential_process templates are maintained in `references/profile-catalog.md`.

Allowed initialization:

1. Create `~/.aws/` if it does not exist.
2. Create `~/.aws/config` if it does not exist.
3. Append the selected known profile stanza when the profile is absent.
4. Preserve all existing profile stanzas and comments.
5. Never write static credentials to `~/.aws/credentials`.

Known profile stanzas:

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"

[profile aws-caad-admin-role]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role"

[profile CA-Nic-prd]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/CA-Nic-prd"
```

Stop and ask before modifying `~/.aws/config` when:

- The selected profile name is not in the known profile list.
- The profile already exists but points to a different `credential_process`.
- The config file contains unusual generated blocks or syntax that would make a safe append/update ambiguous.

After AWS_PROFILE and profile config are confirmed, the default read-only health check must match the final command's profile injection. For AWS CLI inspection, use `--profile`:

```bash
env -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  -u AWS_PROFILE \
  -u AWS_REGION \
  aws sts get-caller-identity --profile <selected-profile> --region ap-northeast-1
```

For Terraform/CDK, verify with the same environment style as the real command:

```bash
env -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  AWS_PROFILE=<selected-profile> \
  AWS_REGION=ap-northeast-1 \
  terraform plan
```

Use `command -v aws` when choosing an AWS CLI binary. Do not hardcode `/usr/local/bin/aws` unless you verified that the current shell's `aws` shim is polluted or broken and that `/usr/local/bin/aws` exists.

Use the same care for `perman-aws-vault`: interactive shells may find it while `credential_process` under `/bin/sh` cannot. If the executable is outside the non-interactive PATH, use the absolute executable path in diagnostics and propose a `credential_process` that can see it.

For S3 read-only checks:

- "List buckets" means `aws s3 ls --profile <profile> --region ap-northeast-1`.
- "List objects" requires an explicit bucket and optional prefix. Ask for the bucket/prefix before running object listing commands.

### Authentication Management

Handle authentication and credential lifecycle:

0. Discover AWS_PROFILE first. If it is unknown, ambiguous, or polluted, stop.
1. Find the existing `perman-aws-vault` executable. If it is missing, stop without install instructions as an action to run.
2. Check AWS CLI config: Ensure `~/.aws/config` exists and the selected profile has `credential_process`
   - If the selected profile is known and missing, initialize the `credential_process` stanza first
   - If the profile is unknown or already exists with conflicting settings, **prompt the user and stop** before running AWS CLI
   - Prompt template:
     - "`~/.aws/config` の対象profileが未知または既存設定と競合しているため、自動更新せず停止します。必要な `credential_process` 設定を確認してください。"
3. Check credential validity with `perman-aws-vault print -p <config-path>` before attempting interactive authentication.
4. Do not manually export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or `AWS_SESSION_TOKEN` when `credential_process` is configured. Manual export is an exceptional fallback and must be cleared before returning to profile-based execution.
5. Handle authentication errors: guide the user through `perman-aws-vault select` only when `print -p` indicates credentials/setup are unavailable
   - `perman-aws-vault select` is treated as interactive unless the installed CLI help explicitly documents non-interactive flags
   - During `select`, stop for browser/user approval whenever `Authentication Message: <digits>` appears; the user must verify the same number in PERMAN Federation before approving
   - `select` writes `.perman-aws-vault` in the current working directory. When setting up a named profile, move or copy that generated file to the selected profile's config directory, for example `~/.config/perman-aws-vault/CA-Nic-prd/.perman-aws-vault`, then remove the accidental project-local file.
   - After `select`, rerun `print -p <config-path>` and then STS using the same profile injection style as the final command. Confirm `Arn`, `Account`, AWS_PROFILE, and config path line up.
   - If AWS STS returns `ValidationError: The requested DurationSeconds exceeds the MaxSessionDuration set for this role`, do not try to fix it with a local `duration_seconds` key. perman-aws-vault sends the `session_duration` returned by PERMAN Federation to `AssumeRoleWithSAML`; the fix is to align the PERMAN Service Provider session duration or the IAM role MaxSessionDuration.

### Command Execution Patterns

Execute AWS commands using the appropriate method:

#### Method 1: AWS Profile (Preferred for credential_process)

```bash
# Option 1: Specify profile per command
aws [service] [operation] --profile <discovered-profile>

# Option 2: Set default profile for session
export AWS_PROFILE=<discovered-profile>
aws [service] [operation]
```

This is the **recommended method** when credential_process is configured in `~/.aws/config`. AWS CLI automatically retrieves credentials through perman-aws-vault.

If `~/.aws/config` is missing or the discovered known profile is not defined: initialize the selected known profile stanza before running AWS CLI. Do not invent a profile solely from environment keywords.

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"
```

```bash
export AWS_PROFILE=<discovered-profile>
```

⚠️ Important: If environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN) are already set, they will **override** AWS_PROFILE. In such cases:

```bash
# Clear existing environment variables first
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE=<discovered-profile>
```

Or start a new shell session to ensure a clean environment.

#### Method 2: perman-aws-vault exec

```bash
perman-aws-vault exec [command]
```

Use only when `credential_process` cannot satisfy the workflow and the target command explicitly requires credentials as environment variables. Prefer AWS_PROFILE for Terraform/CDK.

## Quick Start

### Core Commands

#### 1. Find existing executable

Do not install perman-aws-vault during normal task execution. Search for an existing executable and stop if none is found:

```bash
command -v perman-aws-vault
mise which perman-aws-vault
```

Also check `/opt/homebrew/bin/perman-aws-vault`, `/usr/local/bin/perman-aws-vault`, and `~/.mise/shims/perman-aws-vault`.

#### 2. `perman-aws-vault print`

Output credentials in JSON format for the discovered AWS_PROFILE config path. This is the first authentication check.

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/<discovered-profile>
```

If this succeeds, do not run `select`.

#### 3. `perman-aws-vault select`

Interactively select Service Provider and execute PERMAN Federation SAML authentication.

```bash
perman-aws-vault select
```

Execution flow:

1. Authentication request email notification from PERMAN Federation
2. CLI displays authentication message (e.g., `Authentication Message: <digits>`)
3. Log in to PERMAN Federation via browser and verify authentication message
4. Enter user code to authorize authentication request
5. Select from available Service Provider list

Run this only after `print -p <config-path>` fails because authentication/setup is required. Treat this as an interactive flow by default. Do not invent Service Provider / role command-line flags unless `perman-aws-vault select --help` in the current environment documents them. When connecting to CA-Nic-prd, select Service Provider `CA-Nic-prd` and role label `aws-ca-nic-prd-developer`.

`select` creates `.perman-aws-vault` in the current working directory. For profile-based `credential_process`, place that file under the configured profile directory:

```bash
mkdir -p ~/.config/perman-aws-vault/CA-Nic-prd
cp .perman-aws-vault ~/.config/perman-aws-vault/CA-Nic-prd/.perman-aws-vault
rm .perman-aws-vault
```

The file contains the Service Provider ID, not AWS credentials.

#### 4. `perman-aws-vault exec`

Execute command with temporary security credentials set as environment variables.

```bash
perman-aws-vault exec aws s3 ls
perman-aws-vault exec terraform plan
```

## AWS CLI Integration

### credential_process Configuration

Add the following to `~/.aws/config` to automatically retrieve credentials when executing AWS CLI:

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"

[profile aws-caad-admin-role]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role"

[profile CA-Nic-prd]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/CA-Nic-prd"
```

### Usage Examples

```bash
# Execute AWS CLI commands with profile specification
aws s3 ls --profile <discovered-profile>
aws sts get-caller-identity --profile <discovered-profile> --region ap-northeast-1

# Set default profile for tools that read AWS_PROFILE
export AWS_PROFILE=<discovered-profile>
aws s3 ls
```

## Security Considerations

### Authentication Message Verification

Critical: Always verify that the authentication message displayed in CLI matches the authentication message shown in PERMAN Federation web interface. This is extremely important for security.

```bash
$ perman-aws-vault select
Authentication Message: <digits>  👈 Verify this number matches web interface
```

### User Code Management

- User code is an arbitrary value different from PERMAN password
- Used as secret information to authorize authentication request transmission in CIBA authentication flow
- If forgotten, requires unlinking and reconfiguring connected apps (see `references/setup-guide.md` for details)

### Temporary Security Credentials

- perman-aws-vault issues temporary security credentials only
- Understand expiration time (Expiration) and re-authenticate when expired
- DurationSeconds is controlled by PERMAN Federation's `session_duration` for the selected Service Provider. If it exceeds the IAM role MaxSessionDuration, local config cannot shorten it; update PERMAN/IAM role settings instead.

## Resources

This skill includes references with detailed usage and best practices for perman-aws-vault:

### references/setup-guide.md

Initial setup procedures, user code management, troubleshooting.

#### When to reference

- Setting up perman-aws-vault for the first time
- Forgetting user code
- Confirming installation method

### references/authentication-flow.md

Detailed PERMAN Federation CIBA authentication flow, authentication message verification method, security best practices.

#### When to reference

- Understanding authentication mechanism
- Troubleshooting authentication errors
- Explaining security verification procedures

### references/aws-profiles.md

Available profile details, AWS CLI integration configuration, usage examples, business use case guidelines.

#### When to reference

- Uncertain about profile selection
- Confirming credential_process configuration method
- Learning Terraform usage methods

### references/profile-catalog.md

Canonical table of known profile examples, alias wording, config paths, regions, and `credential_process` templates that this skill may use for safe `~/.aws/config` auto-init.

#### When to reference

- Checking whether a profile is known to the skill
- Updating profile examples or alias wording such as `ndev`
- Confirming safe auto-init targets for `~/.aws/config`

### references/advanced-usage.md

Policy specification, AssumeRoleWithSAML parameters, project-specific configuration, best practices.

#### When to reference

- Requiring permission-restricted sessions
- Applying custom policies
- Needing different configurations per project

## Common Scenarios

### Scenario 1: AWS_PROFILE Found and Credentials Cached

User request: "List S3 buckets in this repository's AWS environment"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Search `.env*`, `mise.toml`, `mise.local.toml`, Terraform execution directory, and `echo $AWS_PROFILE`
3. Confirm exactly one usable AWS_PROFILE value
4. Find an existing perman-aws-vault executable without installing anything
5. Run `perman-aws-vault print -p ~/.config/perman-aws-vault/<AWS_PROFILE>`
6. If print succeeds, run the read-only AWS CLI command with the same profile

### Scenario 2: Production Mentioned but AWS_PROFILE Missing

User request: "Run production Terraform plan"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Search concrete AWS_PROFILE sources
3. If AWS_PROFILE is not found, stop
4. Report that production/CAAD wording is insufficient to choose a profile
5. Ask for the correct AWS_PROFILE or the env file/mise context that defines it

### Scenario 3: perman-aws-vault Is Outside PATH

Situation: `command -v perman-aws-vault` fails, but `/opt/homebrew/bin/perman-aws-vault` exists.

#### Subagent workflow

1. Report the executable found at `/opt/homebrew/bin/perman-aws-vault`
2. Do not run `brew install`
3. Use that executable path for `print -p`
4. If `credential_process` uses bare `perman-aws-vault`, warn that `/bin/sh` PATH may not find it and propose a config update before Terraform/CDK execution

### Scenario 4: ~/.aws/config Missing or Profile Undefined

User request: "Run aws s3 ls with perman-aws-vault"

#### Subagent workflow

1. Discover AWS_PROFILE first
2. If the discovered profile is known and absent from `~/.aws/config`, create `~/.aws/` and/or append the exact `credential_process` stanza while preserving existing settings
3. Confirm the perman-aws-vault config path exists, for example `~/.config/perman-aws-vault/<AWS_PROFILE>`
4. Run `print -p` first
5. If `print -p` requires setup/authentication, run or guide `perman-aws-vault select`; the user must verify the authentication message before approval
6. Retry the read-only AWS command with the same profile injection style

### Scenario 5: Terraform Usage

User request: "Deploy resources with Terraform"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Discover AWS_PROFILE from `.env*`, `mise.toml`, current shell, and the Terraform execution directory. Stop if not unique.
3. Ensure clean environment for credential_process to work:
   - Check if AWS environment variables (AWS_ACCESS_KEY_ID, etc.) are set
   - If set, use command-scoped `env -u` or recommend a clean shell
   - Set AWS_PROFILE to the discovered value
4. Run `perman-aws-vault print -p ~/.config/perman-aws-vault/<AWS_PROFILE>` before interactive auth
5. Execute non-destructive Terraform commands first with the same AWS_PROFILE injection as the later apply:

   ```bash
   AWS_PROFILE=<discovered-profile> terraform init
   AWS_PROFILE=<discovered-profile> terraform plan
   ```

6. Confirm workspace/backend/var-file/stack selectors before producing any apply/deploy command
7. Ask for explicit confirmation before `terraform apply` or CDK deploy
8. Handle authentication refresh with `print -p` first if credentials expire during execution
9. Note: Terraform provider configuration does not need an explicit `profile` parameter when the repository supplies AWS_PROFILE and `credential_process` is configured.

### Scenario 6: Multi-environment Deployment

User request: "Deploy to both staging and production"

#### Subagent workflow

1. Choose subagent delegation if available because this is multi-environment work
2. Discover AWS_PROFILE separately for each target environment from that environment's `.env*`, `mise.toml`, and Terraform execution context
3. Stop if either environment's AWS_PROFILE is missing or ambiguous
4. Execute staging first only after its profile is verified with `print -p` and plan
5. Request explicit confirmation before production deployment
6. Execute production only after production AWS_PROFILE, `print -p`, plan, and environment selectors are fixed
