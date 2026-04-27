---
name: perman-aws-vault
description: Specialized skill for AWS CLI commands and AWS resource management using perman-aws-vault. Provides PERMAN Federation SAML authentication guidance, temporary credential handling through credential_process/keychain, and automatic AWS profile selection for nearshore/CAAD use cases. Trigger when users mention AWS services (S3, EC2, Lambda, RDS), AWS CLI/profile/configuration, Terraform/CDK with AWS credentials, ~/.aws/ files, or AWS authentication. Supports delegation to a subagent when the current runtime provides one, but can also be used directly for simple or clearly scoped operations.
---

# perman-aws-vault

## Overview

PERMAN Federation SAML認証を通じてAWS一時的セキュリティ認証情報を取得し、keychainなどのキーストアで安全に管理するツール。AWS CLIの`credential_process`と統合することで、AWS操作時の認証を自動化する。

このスキルは、AWS環境の判定、profile選択、認証管理、コマンド実行の安全な進め方を決めるために使う。実行環境がsubagentを提供している場合は、複数ステップや影響範囲の大きいAWS操作をsubagentへ委譲してよい。subagentが使えない場合や、profileが明確な単発の読み取り操作では直接進める。

## How to Use This Skill

### Execution Mode

Choose the smallest safe execution mode:

- Direct execution / direct response: Use for simple, one-off commands where the profile is already known, especially read-only operations.
- Subagent delegation: Use when the runtime provides subagents and the task is multi-step, needs project-context inspection, may affect infrastructure, or mixes AWS CLI/Terraform/CDK work.
- Stop and ask/setup: Use when the AWS environment, profile, `~/.aws/config`, Terraform workspace/backend/var-file, or production approval is unclear.

When delegating, pass the subagent the user request, working directory, detected environment clues, selected profile if known, and the safety rules from this skill. The subagent must:

1. Analyze the request to determine the appropriate AWS environment (nearshore/CAAD, staging/production)
2. Select the correct AWS profile automatically
3. Check authentication/configuration preconditions before running commands
4. Execute only commands that are safe for the confirmed environment and approval state
5. Report results back to the user

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
aws s3 ls --profile aws-caad-ndev-admin
aws ec2 describe-instances --profile aws-caad-admin-role
```

Before direct execution, still apply the preflight checks below.

### Preflight and Safety Gates

Before running AWS CLI, Terraform, CDK, or a command plan that assumes credentials:

1. Select the profile first using the environment rules below.
2. Check `~/.aws/config`. If the selected profile is missing or has no `credential_process`, stop before AWS execution and provide the config snippet for that profile.
3. Check AWS credential environment variables. If `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, or `AWS_SESSION_TOKEN` is set, unset them or start a clean shell before relying on `AWS_PROFILE`.
4. Prefer `credential_process` with `--profile` or `AWS_PROFILE`. Use manual environment-variable export only when `credential_process` cannot be used and the user explicitly needs it.
5. Never expose or request secret values. Ask the user to run authentication/setup locally instead.
6. Require explicit confirmation before production/CAAD changes. Read-only CAAD inspection can proceed after profile/config checks, but production deploy/apply/delete/update operations must stop for confirmation. Words such as "見たい", "確認したい", or "あとで適用も" are not approval; ask for an explicit `y/n` or equivalent confirmation before showing or running an apply/deploy command.
7. For Terraform/CDK, confirm the project-specific workspace, backend, var-file, stack, or context before apply/deploy. If unknown, provide only non-destructive discovery or plan commands with placeholders, list the missing selectors, and ask for the selectors before producing a concrete apply/deploy command.

When a required input is missing, report it as **Blocked preconditions** instead of treating it as permission to guess:

- Missing AWS profile/config: stop before AWS execution and show the needed `credential_process` snippet.
- Missing Terraform/CDK selector: list the missing workspace/backend/var-file/stack/context/app path and stay on discovery/plan.
- Missing production approval: ask for explicit approval after the plan/diff target is fixed.

## When to Use This Skill

Trigger this skill when:

- User requests AWS CLI command execution
- AWS resource operations are needed (S3, EC2, Lambda, RDS, etc.)
- Switching between multiple AWS accounts is required
- Business use cases mention "nearshore environment", "CAAD environment", "staging", or "production"
- Questions about AWS authentication or profile configuration arise
- Working with Terraform requiring AWS credentials
- `~/.aws/` configuration files are referenced

## Subagent Workflow

### Environment Detection

To determine the appropriate AWS environment:

1. Check explicit mentions: Look for "nearshore", "ndev", "CAAD", "staging", "production"
2. Analyze project context: Examine current working directory (e.g., `caad-loca-cdk`, `caad-asta`), Terraform/CDK configurations, or `.perman-aws-vault` files
3. Infer from operation type: Development/test operations suggest nearshore, production operations suggest CAAD
4. Ask user when unclear: Present environment options and request selection

#### Auto-detection by project directory

- `caad-loca-cdk/` → `aws-caad-ndev-admin` (Nearshore)
- `caad-sereca-cdk/` → `aws-caad-ndev-admin` (Nearshore)
- `caad-asta/` → `aws-caad-ndev-admin` (Nearshore)
- `caad-sereca/` → `aws-caad-ndev-admin` (Nearshore)
- `caad-loca-bff/` → `aws-caad-ndev-admin` (Nearshore)

### Profile Selection Strategy

Map detected environment to AWS profile:

- Nearshore environment: Use `aws-caad-ndev-admin`
  - Keywords: "nearshore", "ndev", "asta", "sereca", "loca"
  - Projects: `caad-asta`, `caad-sereca`, `caad-loca-bff`, `caad-loca-cdk`, `caad-sereca-cdk`
  - Use cases: Development, testing, staging deployments

- CAAD environment: Use `aws-caad-admin-role`
  - Keywords: "CAAD", "production"
  - Use cases: Production deployments, CAAD-specific operations

### Authentication Management

Handle authentication and credential lifecycle:

0. Check AWS CLI config: Ensure `~/.aws/config` exists and the selected profile has `credential_process`
   - If missing or profile undefined, **prompt the user to set it up and stop** before running AWS CLI
   - Prompt template:
     - "`~/.aws/config` が見つからない/対象profileが未定義のため、`credential_process` の設定をお願いします。設定後に `AWS_PROFILE` を指定して再実行してください。必要なら手順を案内します。"
1. Check credential validity: Verify current credentials are not expired
2. Refresh when needed: Execute `perman-aws-vault print` to obtain fresh credentials
3. Export environment variables: Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
4. Handle authentication errors: Guide user through `perman-aws-vault select` if credentials are unavailable

### Command Execution Patterns

Execute AWS commands using the appropriate method:

#### Method 1: AWS Profile (Preferred for credential_process)

```bash
# Option 1: Specify profile per command
aws [service] [operation] --profile aws-caad-ndev-admin

# Option 2: Set default profile for session
export AWS_PROFILE=aws-caad-ndev-admin
aws [service] [operation]
```

This is the **recommended method** when credential_process is configured in `~/.aws/config`. AWS CLI automatically retrieves credentials through perman-aws-vault.

If `~/.aws/config` is missing or the profile is not defined: prompt the user to set it up before running AWS CLI, and suggest setting `AWS_PROFILE` for convenience:

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"
```

```bash
export AWS_PROFILE=aws-caad-ndev-admin
```

⚠️ Important: If environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN) are already set, they will **override** AWS_PROFILE. In such cases:

```bash
# Clear existing environment variables first
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_PROFILE=aws-caad-ndev-admin
```

Or start a new shell session to ensure a clean environment.

#### Method 2: perman-aws-vault exec

```bash
perman-aws-vault exec [command]
```

Use when you need to execute commands with credentials set as environment variables directly.

#### Method 3: Environment Variables (Manual)

```bash
eval "$(perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin/ | jq -r '"export AWS_ACCESS_KEY_ID=\(.AccessKeyId) AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey) AWS_SESSION_TOKEN=\(.SessionToken)"')" && [command]
```

Use when credential_process is not configured, or when you need explicit control over credential management. Note that setting these environment variables will prevent AWS_PROFILE from working until they are unset.

## Quick Start

### Core Commands

#### 1. `perman-aws-vault select`

Interactively select Service Provider and execute PERMAN Federation SAML authentication.

```bash
perman-aws-vault select
```

Execution flow:

1. Authentication request email notification from PERMAN Federation
2. CLI displays authentication message (e.g., `Authentication Message: 611456`)
3. Log in to PERMAN Federation via browser and verify authentication message
4. Enter user code to authorize authentication request
5. Select from available Service Provider list

#### 2. `perman-aws-vault exec`

Execute command with temporary security credentials set as environment variables.

```bash
perman-aws-vault exec aws s3 ls
perman-aws-vault exec terraform plan
```

#### 3. `perman-aws-vault print`

Output credentials in JSON format (for `credential_process`).

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
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
```

### Usage Examples

```bash
# Execute AWS CLI commands with profile specification
aws s3 ls --profile aws-caad-ndev-admin
aws ec2 describe-instances --profile aws-caad-admin-role

# Set default profile
export AWS_PROFILE=aws-caad-ndev-admin
aws s3 ls
```

## Available Profiles

### aws-caad-ndev-admin

- Purpose: Nearshore account
- Configuration file: `~/.config/perman-aws-vault/aws-caad-ndev-admin`
- Recommended scenarios: Development, testing, nearshore-related operations

### aws-caad-admin-role

- Purpose: CAAD account
- Configuration file: `~/.config/perman-aws-vault/aws-caad-admin-role`
- Recommended scenarios: Production, CAAD-related operations

## Security Considerations

### Authentication Message Verification

Critical: Always verify that the authentication message displayed in CLI matches the authentication message shown in PERMAN Federation web interface. This is extremely important for security.

```bash
$ perman-aws-vault select
Authentication Message: 611456  👈 Verify this number matches web interface
```

### User Code Management

- User code is an arbitrary value different from PERMAN password
- Used as secret information to authorize authentication request transmission in CIBA authentication flow
- If forgotten, requires unlinking and reconfiguring connected apps (see `references/setup-guide.md` for details)

### Temporary Security Credentials

- perman-aws-vault issues temporary security credentials only
- Understand expiration time (Expiration) and re-authenticate when expired

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

### references/advanced-usage.md

Policy specification, AssumeRoleWithSAML parameters, project-specific configuration, best practices.

#### When to reference

- Requiring permission-restricted sessions
- Applying custom policies
- Needing different configurations per project

## Common Scenarios

### Scenario 1: User Requests AWS CLI Command Execution

User request: "List S3 buckets"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Subagent detects environment is unclear
3. Ask user: "Which environment's S3 buckets to check?"
   - Nearshore environment (aws-caad-ndev-admin)
   - CAAD environment (aws-caad-admin-role)
4. User selects "Nearshore"
5. Execute: `aws s3 ls --profile aws-caad-ndev-admin`

### Scenario 2: Environment Explicitly Specified

User request: "Get EC2 instance list in CAAD environment"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Subagent detects "CAAD environment" keyword
3. Automatically select `aws-caad-admin-role` profile
4. Execute: `aws ec2 describe-instances --profile aws-caad-admin-role`

### Scenario 3: Authentication Error Occurs

Error: Unable to locate credentials

#### Subagent workflow

1. Detect credential error
2. Report to user: "Credentials not found. Authenticate with: `perman-aws-vault select`"
3. Wait for user authentication
4. Retry AWS CLI command after authentication

### Scenario 4: ~/.aws/config Missing or Profile Undefined

User request: "Run aws s3 ls with perman-aws-vault"

#### Subagent workflow

1. Detect missing `~/.aws/config` or profile definition
2. Prompt user to add `credential_process` config
3. Suggest setting `AWS_PROFILE` (or using `--profile`)
4. Proceed after confirmation

### Scenario 5: Terraform Usage

User request: "Deploy resources to nearshore environment with Terraform"

#### Subagent workflow

1. Choose direct response or subagent delegation based on runtime support and task size
2. Ensure clean environment for credential_process to work:
   - Check if AWS environment variables (AWS_ACCESS_KEY_ID, etc.) are set
   - If set, recommend starting a new shell or unsetting them
   - Set AWS_PROFILE: `export AWS_PROFILE=aws-caad-ndev-admin`
3. Execute non-destructive Terraform commands first (credential_process automatically handles authentication):

   ```bash
   terraform init
   terraform plan
   ```

4. Confirm workspace/backend/var-file/stack selectors before producing any apply/deploy command
5. Ask for explicit confirmation before `terraform apply` or CDK deploy
6. Handle authentication refresh if credentials expire during execution
7. Note: Terraform provider configuration does NOT need explicit `profile` parameter when using credential_process - AWS_PROFILE environment variable is sufficient

### Scenario 6: Multi-environment Deployment

User request: "Deploy to both staging and production"

#### Subagent workflow

1. Choose subagent delegation if available because this is multi-environment work
2. Subagent creates deployment plan:
   - Staging: Use `aws-caad-ndev-admin`
   - Production: Use `aws-caad-admin-role`
3. Execute staging deployment first
4. Request explicit confirmation before production deployment
5. Execute production deployment with `aws-caad-admin-role` only after confirmation and environment selectors are fixed

## Notes

- credential_process: AWS CLI standard feature for retrieving credentials from external programs
- CIBA (Client Initiated Backchannel Authentication): OpenID Connect extension specification for device-mediated authentication flow
- Temporary Security Credentials: Composed of AccessKeyId, SecretAccessKey, and SessionToken with expiration time
- SAML (Security Assertion Markup Language): Standard for exchanging user authentication information between different security domains
