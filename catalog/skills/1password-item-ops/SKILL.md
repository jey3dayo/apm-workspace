---
name: 1password-item-ops
description: Use when working with 1Password CLI (`op`) to find, inspect, create, edit, or update 1Password items such as logins, secure notes, API credentials, service account token items, repo-specific dotenvx `.env.keys` file attachments, and related secrets. Default to the Personal vault unless the user names another vault, use dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when provided for authentication, search before changing items, avoid exposing secret values, and require confirmation for ambiguous or destructive operations.
---

# 1Password Item Ops

Use this skill to manage 1Password items through `op` while keeping secrets out of the conversation and logs.

## Defaults

- Default vault: `Personal`.
- If the user names a vault, use that vault exactly. For automation-only tasks, `Automation` is a common explicit vault.
- Prefer an existing authenticated `op` session. If none exists, prefer these authentication sources in order:
  1. A dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when the repo or user points to `.env` / `.env.keys`.
  2. `OP_SERVICE_ACCOUNT_TOKEN_FILE` when the user provides a token file path.
  3. Manual sign-in only when the user explicitly asks.
- For dotenvx-managed service accounts, shape commands as:

```bash
dotenvx run -f <env-file> -fk <env-keys-file> -- op <command>
```

- If `Personal` matches multiple vaults, run `op vault list --format json`, identify the likely personal vault ID, and confirm before changing anything when ambiguity remains.
- Do not install public 1Password skills or new credential tooling unless the user explicitly asks.
- For service accounts, verify create/edit permission before changing items; successful list/read commands only prove read access.

## Workflow

1. Verify `op` is available with `command -v op` or `op --version`.
2. Resolve the target vault.
   - Use `Personal` by default.
   - Use explicit vault names such as `Automation` when provided by the user.
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
- Prefer `op read --no-newline <secret-reference>` when transferring a secret into another command. Pipe the value directly and only report length/presence when verification is needed.
- When a secret reference includes spaces in the item or field name, prefer the item ID in the reference to avoid shell quoting mistakes.

## Dotenvx and File Attachments

Use this pattern when the user manages 1Password service account tokens through dotenvx:

```bash
dotenvx run -f .env -fk .env.keys -- op vault list
```

Repo-specific policy: dotenvx-encrypted `.env` files may be intentionally committed when that repository follows that practice; `.env.keys` must remain ignored and should be stored as a 1Password file attachment.

For `op item create` / `op item edit` with assignment arguments, protect against accidental JSON stdin parsing:

```bash
op item create --vault Automation --category "Secure Note" \
  --title "example | .env.keys" \
  "env.keys[file]=/path/to/.env.keys" </dev/null
```

Do not put secret values in assignment arguments. For sensitive field updates, prefer JSON templates or `op read` pipelines that do not expose values in command output or shell history.

## Common Item Patterns

Create a software license with non-secret metadata only:

```bash
op item create --vault <vault-id> --category "Software License" \
  --title "<Product Name>" \
  "Customer.registered email[email]=<email>" \
  "Order.purchase date[date]=YYYY-MM-DD" </dev/null
```

Use `Software License` for app licenses by default. Prefer these non-secret fields when available:

- `registered email` for the account email.
- `purchase date` for the date field.
- `Registration Date` as a custom text field when the source gives a timestamp.

For license or credential values, do not pass the real secret as an assignment argument. Create the item with non-secret metadata first, then add sensitive fields through a JSON template, stdin-safe flow, or another method that does not expose the value in shell history or command output.

Use `Login` for sign-in credentials, `Secure Note` for free-form recovery or setup notes, and `API Credential` for service tokens or API keys unless existing 1Password categories in the vault suggest a better match.

## Failure Handling

- If `op item edit` fails with `unsupported field type: ssoLogin`, stop retrying that approach and report that the item needs UI editing or a narrower CLI-safe update.
- If authentication fails, check only whether the token file exists and whether `OP_SERVICE_ACCOUNT_TOKEN_FILE` is set. Do not print token contents.
- After three failures with the same approach, stop and report the attempts, concrete errors, and a different next approach.
