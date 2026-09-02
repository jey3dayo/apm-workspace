---
name: 1password
description: Use when working with 1Password CLI (`op`) to find, inspect, create, edit, or update items such as logins, secure notes, API credentials, service-account token items, and dotenvx `.env.keys` file attachments. Defaults to the Personal vault, authenticates via dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when provided, and never exposes secret values. Covers the `op` CLI only; 1Password Environments and local `.env` file generation belong to the `1password` MCP server. For dotenvx key rotation, `dotenvx` leads the end-to-end procedure; this skill handles only the 1Password item update step.
---

# 1Password

Manage 1Password items through `op` while keeping secrets out of the conversation, shell history, and logs.

## Vault and Authentication

- Default to the `Personal` vault. Use the exact vault the user names (e.g. `Automation` for automation-only tasks). Use vault IDs, not names, when duplicate names exist — if `Personal` matches multiple vaults, run `op vault list --format json`, identify the likely one, and confirm before changing anything.
- Prefer the signed-in account or app integration when available (`--account <id-or-shorthand>` when known). Otherwise authenticate in this order:
  1. Dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when the repo or user points to `.env` / `.env.keys`:

     ```bash
     dotenvx run -f <env-file> -fk <env-keys-file> -- op <command>
     ```

  2. `OP_SERVICE_ACCOUNT_TOKEN_FILE` when the user provides a token file path.
  3. Manual sign-in only when the user explicitly asks.
- Homelab default dotenvx env file: `/home/pi/.config/.env`. Store the bootstrap token there as an `encrypted:` value; never create a plaintext token cache under `/home/pi/.config/op/`.
- Verify create/edit permission for service accounts before changing items; successful list/read only proves read access. If create/edit returns `(101) You do not have permission`, and the vault holds a `Service Account Auth Token: <name>` item, read that item's token into process memory with `op item get <item-id> --fields <concealed-field-id> --reveal`, verify only its prefix/length, and retry with it as `OP_SERVICE_ACCOUNT_TOKEN`.
- Do not install public 1Password skills or new credential tooling unless the user explicitly asks.

## Workflow

1. Verify `op` is available (`command -v op` or `op --version`).
2. Resolve the target vault per the rules above.
3. Search before creating or editing: `op item list --vault <vault-id-or-name> --format json`, narrowed by category or title when given.
4. Decide whether to proceed:
   - Proceed for one low-risk item when the target, vault, category, and non-secret fields are clear.
   - Ask for OK/NG before multiple item changes, bulk registration, rename, delete, vault move, destructive update, or ambiguous candidate selection.
5. Execute the minimal `op item create` or `op item edit` command.
6. Read back only safe fields: item ID, title, category, vault, non-secret fields. Mask secret fields.

## Secret Handling

- Never print passwords, tokens, license IDs, recovery keys, TOTP seeds, private keys, or full credential values. Report presence, prefix/length, or a masked value only.
- Treat user-provided masked values such as `o-xxxxxxxxxxxxxxxx` as intentional placeholders unless the user provides the real value and asks to store it.
- Include only item ID, title, category, vault, and non-secret metadata in final reports.
- Avoid shell tracing and verbose modes that may echo secrets.
- Prefer `op read --no-newline <secret-reference>` when transferring a secret into another command; pipe directly. Use the item ID in the reference when item or field names contain spaces.

## Item Creation and Editing

Protect assignment-argument commands against accidental JSON stdin parsing with `</dev/null`:

```bash
op item create --vault Automation --category "Secure Note" \
  --title "example | .env.keys" \
  "env.keys[file]=/path/to/.env.keys" </dev/null
```

Never put secret values in assignment arguments — they land in shell history and command output. Create the item with non-secret metadata first, then add sensitive fields via a JSON template or an `op read` stdin pipeline.

Category defaults: `Login` for sign-in credentials, `Secure Note` for free-form recovery/setup notes, `API Credential` for service tokens or API keys, `Software License` for app licenses — unless existing items in the vault suggest a better match.

Software License pattern (non-secret metadata only):

```bash
op item create --vault <vault-id> --category "Software License" \
  --title "<Product Name>" \
  "Customer.registered email[email]=<email>" \
  "Order.purchase date[date]=YYYY-MM-DD" </dev/null
```

Prefer `registered email`, `purchase date`, and a custom `Registration Date` text field when the source gives a timestamp.

## Dotenvx and File Attachments

- Dotenvx-encrypted `.env` files may be intentionally committed when that repository follows the practice; `.env.keys` must remain ignored and should be stored as a 1Password file attachment.
- On Windows/PowerShell, dotenvx's shim can misparse options after `--`, especially when the executable path contains spaces. If `op` options are reported as dotenvx options, inject the token process-locally instead:

  ```powershell
  $env:OP_SERVICE_ACCOUNT_TOKEN = (dotenvx get OP_SERVICE_ACCOUNT_TOKEN -f .env --quiet)
  try {
    & "$env:LOCALAPPDATA\Programs\1Password CLI\op.exe" vault list --format json
  } finally {
    Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
  }
  ```

## Hermes Codex App Token Rotation

For rotating the homelab Hermes Agent Codex app token from 1Password into the Kubernetes Pod, follow `references/hermes-codex-token-rotation.md` (item IDs, safe read/rotation/verification command patterns, backup rules).

## Failure Handling

- If `op item edit` fails with `unsupported field type: ssoLogin`, stop retrying that approach and report that the item needs UI editing or a narrower CLI-safe update.
- If authentication fails, check only whether the env file contains the `OP_SERVICE_ACCOUNT_TOKEN` key and whether dotenvx can inject it. Do not print token contents.
- After three failures with the same approach, stop and report the attempts, concrete errors, and a different next approach.

## Done When

- The requested item change is applied (or explicitly declined pending user confirmation), verified by reading back non-secret fields.
- No secret value appeared in commands, output, or the final report.
- The report lists item ID, title, category, and vault for every touched item.
