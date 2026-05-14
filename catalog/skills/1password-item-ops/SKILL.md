---
name: 1password-item-ops
description: Use when working with 1Password CLI (`op`) to find, inspect, create, edit, or update 1Password items such as logins, software licenses, secure notes, API credentials, and related secrets. Default to the Personal vault, search before changing items, avoid exposing secret values, require user confirmation for ambiguous vaults, multiple candidates, bulk changes, renames, deletes, vault moves, or destructive operations, and use the service-account token file when available.
---

# 1Password Item Ops

Use this skill to manage 1Password items through `op` while keeping secrets out of the conversation and logs.

## Defaults

- Default vault: `Personal`.
- Default token file: `/Users/t00114/.config/op/service-account-token`.
- Prefer commands shaped as:

```bash
OP_SERVICE_ACCOUNT_TOKEN_FILE=/Users/t00114/.config/op/service-account-token op <command>
```

- If `Personal` matches multiple vaults, run `op vault list --format json`, identify the likely personal vault ID, and confirm before changing anything when ambiguity remains.
- Do not install public 1Password skills or new credential tooling unless the user explicitly asks.

## Workflow

1. Verify `op` is available with `command -v op` or `op --version`.
2. Resolve the target vault.
   - Use `Personal` by default.
   - Use the vault ID, not the name, when duplicate vault names exist.
3. Search before creating or editing.
   - Use `op item list --vault <vault-id-or-name> --format json`.
   - Narrow by category or title when the user provides one.
4. Decide whether to proceed.
   - Proceed for one low-risk item when the target, vault, category, and non-secret fields are clear.
   - Ask for OK/NG before multiple item changes, bulk registration, rename, delete, vault move, destructive update, or ambiguous candidate selection.
5. Execute the minimal `op item create` or `op item edit` command.
6. Read back only safe fields: item ID, title, category, vault, and non-secret fields. Mask secret fields.

## Secret Handling

- Never print passwords, tokens, license IDs, recovery keys, TOTP seeds, private keys, or full credential values.
- Treat user-provided masked values such as `o-xxxxxxxxxxxxxxxx` as intentional placeholders unless the user provides the real value and asks to store it.
- In final reports, include only item ID, title, category, vault, and non-secret metadata.
- When checking whether a secret exists, report presence or a masked value only.
- Avoid shell tracing and verbose command modes that may echo secrets.

## Common Item Patterns

Create a software license when a user provides product/license metadata:

```bash
OP_SERVICE_ACCOUNT_TOKEN_FILE=/Users/t00114/.config/op/service-account-token \
op item create --vault <vault-id> --category "Software License" \
  --title "<Product Name>" \
  reg_code="<masked-or-secret-license-id>" \
  "Customer.registered email[email]=<email>" \
  "Order.purchase date[date]=YYYY-MM-DD"
```

Use `Software License` for app licenses by default. Prefer these fields when available:

- `license key` (`reg_code`) for the license ID or key.
- `registered email` for the account email.
- `purchase date` for the date field.
- `Registration Date` as a custom text field when the source gives a timestamp.

Use `Login` for sign-in credentials, `Secure Note` for free-form recovery or setup notes, and `API Credential` for service tokens or API keys unless existing 1Password categories in the vault suggest a better match.

## Failure Handling

- If `op item edit` fails with `unsupported field type: ssoLogin`, stop retrying that approach and report that the item needs UI editing or a narrower CLI-safe update.
- If authentication fails, check only whether the token file exists and whether `OP_SERVICE_ACCOUNT_TOKEN_FILE` is set. Do not print token contents.
- After three failures with the same approach, stop and report the attempts, concrete errors, and a different next approach.
