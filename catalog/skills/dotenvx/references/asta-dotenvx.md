# ASTA dotenvx Notes

Use this reference when working in `caad-asta` or another CAAD repo with dotenvx, mise, AWS CLI, or perman-aws-vault.

## Current Pattern

- `.env`, `.env.dev`, and `.env.example` may contain local or example values.
- `.env.development`, `.env.staging`, and `.env.production` may contain dotenvx `encrypted:` values.
- `mise` tasks or shims can place env values into the process before a command runs.
- AWS deployment and inspection commonly uses the nearshore profile `aws-caad-ndev-admin` and region `ap-northeast-1`, but confirm with the `perman-aws-vault` skill before changing infrastructure.

## Known Failure Mode

In `caad-asta`, AWS CLI failed when the repo environment injected encrypted dotenvx values into AWS variables:

- `AWS_PROFILE=encrypted:...`
- `AWS_REGION=encrypted:...`

The fix was to avoid the injected env and call the AWS binary with explicit clean values:

```bash
env -u AWS_PROFILE -u AWS_DEFAULT_PROFILE \
  -u AWS_REGION -u AWS_DEFAULT_REGION \
  -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
  AWS_PROFILE=aws-caad-ndev-admin \
  AWS_REGION=ap-northeast-1 \
  AWS_DEFAULT_REGION=ap-northeast-1 \
  /usr/local/bin/aws sts get-caller-identity
```

Successful signal was `sts get-caller-identity` returning the expected account and role through perman-aws-vault.

## Operational Split

- `dotenvx run`: use for app commands that intentionally need decrypted app configuration.
- Clean env: use for AWS CLI, Terraform, CDK, GitHub CLI, Git, and perman-aws-vault unless a repo task explicitly documents otherwise.
- Direct binary path: use when a shim, task runner, or shell hook keeps injecting encrypted app env into tooling commands.

## Reporting

When reporting results:

- State which env file was used, not the secret values.
- State which AWS profile/region was selected.
- State whether the command ran inside dotenvx or a clean env.
- Redact or omit any credential-like value.
