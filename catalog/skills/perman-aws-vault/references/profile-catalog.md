# Profile Catalog

This catalog lists known `perman-aws-vault` profiles that this skill may treat as safe initialization targets for `~/.aws/config`.

Do not use this table as the source of truth for selecting an AWS profile. Always discover `AWS_PROFILE` from the user request, current shell, repository env files, or task configuration first. Alias and environment wording are only fallback context.

## Known Profiles

| Profile               | Business context                 | PERMAN service provider / role label   | Config path                                      | Region           | Safe `~/.aws/config` auto-init |
| --------------------- | -------------------------------- | -------------------------------------- | ------------------------------------------------ | ---------------- | ------------------------------ |
| `aws-caad-ndev-admin` | Nearshore/development account    | Unknown / not documented here          | `~/.config/perman-aws-vault/aws-caad-ndev-admin` | `ap-northeast-1` | Yes                            |
| `aws-caad-admin-role` | CAAD account                     | Unknown / not documented here          | `~/.config/perman-aws-vault/aws-caad-admin-role` | `ap-northeast-1` | Yes                            |
| `CA-Nic-prd`          | CA-Nic production developer role | Role label: `aws-ca-nic-prd-developer` | `~/.config/perman-aws-vault/CA-Nic-prd`          | `ap-northeast-1` | Yes                            |

## Alias And Wording Hints

These hints help explain user wording, but they must not override `AWS_PROFILE` discovery.

| User wording                                       | Candidate profile     | Inference allowed? | Notes                                                   |
| -------------------------------------------------- | --------------------- | ------------------ | ------------------------------------------------------- |
| `ndev`, `nearshore`, `development`                 | `aws-caad-ndev-admin` | No                 | Ask for or discover `AWS_PROFILE` before AWS execution. |
| `CAAD`, `CAAD production`, `caad-admin`            | `aws-caad-admin-role` | No                 | Production or CAAD changes require explicit approval.   |
| `CA-Nic`, `CA-Nic-prd`, `aws-ca-nic-prd-developer` | `CA-Nic-prd`          | No                 | Production changes require explicit approval.           |

## Credential Process Templates

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
