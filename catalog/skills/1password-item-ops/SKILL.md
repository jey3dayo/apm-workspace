---
name: 1password-item-ops
description: Use when working with 1Password CLI (`op`) to find, inspect, create, edit, or update 1Password items such as logins, secure notes, API credentials, service account token items, repo-specific dotenvx `.env.keys` file attachments, and related secrets. Default to the Personal vault unless the user names another vault, use dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when provided for authentication, search before changing items, avoid exposing secret values, and require confirmation for ambiguous or destructive operations.
---

# 1Password Item Ops

Use this skill to manage 1Password items through `op` while keeping secrets out of the conversation and logs.

## Defaults

- Default vault: `Personal`.
- If the user names a vault, use that vault exactly. For automation-only tasks, `Automation` is a common explicit vault.
- Prefer the signed-in 1Password account or app integration when available. Use `--account <account-id-or-shorthand>` when the account is known.
- If no signed-in account or app integration is available, prefer these authentication sources in order:
  1. A dotenvx-managed `OP_SERVICE_ACCOUNT_TOKEN` when the repo or user points to `.env` / `.env.keys`.
  2. `OP_SERVICE_ACCOUNT_TOKEN_FILE` when the user provides a token file path.
  3. Manual sign-in only when the user explicitly asks.
- Homelab default dotenvx env file: `/home/pi/.config/.env`.
- For dotenvx-managed service accounts, shape commands as:

```bash
dotenvx run -f <env-file> -fk <env-keys-file> -- op <command>
```

- Do not create or rely on a plaintext homelab token cache under `/home/pi/.config/op/`; the bootstrap token belongs in `/home/pi/.config/.env` as an encrypted dotenvx value.
- If `Personal` matches multiple vaults, run `op vault list --format json`, identify the likely personal vault ID, and confirm before changing anything when ambiguity remains.
- Do not install public 1Password skills or new credential tooling unless the user explicitly asks.
- For service accounts, verify create/edit permission before changing items; successful list/read commands only prove read access.
- When a vault contains a service-account token item such as `Service Account Auth Token: <name>`, distinguish the bootstrap token used to read that item from the token stored in the item. If create/edit returns `(101) You do not have permission to perform this action`, read the token item into process memory with `op item get <item-id> --fields <concealed-field-id> --reveal`, verify only its prefix/length, and retry with that token as `OP_SERVICE_ACCOUNT_TOKEN`.

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

On Windows/PowerShell, dotenvx's PowerShell shim can misparse command options after `--`, especially when the target executable path contains spaces. If `op` options are reported as dotenvx options, use a process-local env injection instead of printing secrets:

```powershell
$env:OP_SERVICE_ACCOUNT_TOKEN = (dotenvx get OP_SERVICE_ACCOUNT_TOKEN -f .env --quiet)
try {
  & "$env:LOCALAPPDATA\Programs\1Password CLI\op.exe" vault list --format json
} finally {
  Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
}
```

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

## Hermes Codex App Token Rotation

Use this when rotating the homelab Hermes Agent Codex app token from 1Password into the Kubernetes Pod. The current source item is:

- Vault: `Automation` (`6jathgtxvuygms2t4xt4pjgooe`)
- Item: `Codex Access Token` (`c76zdom3zpwl2l6fnc72oyc7ey`)
- Secret field: `Access Token`
- Hermes profile: `/opt/data/profiles/codex`

Rules:

- Treat 1Password as the source of truth.
- Treat `/home/pi/.config/.env` as the source for the 1Password service-account bootstrap token. `OP_SERVICE_ACCOUNT_TOKEN` should be `encrypted:` there.
- Never write the token to the repository, shell history, or logs.
- Prefer item and vault IDs over names for automation.
- Pipe the secret through stdin directly into the Pod.
- Back up `/opt/data/profiles/codex/auth.json` before replacing the `openai-codex` credential.
- Verify only non-secret metadata: credential label, auth type, model count, and model names.
- The app token is not a refresh-token OAuth session. If it expires, update the 1Password item and run the rotation again.

Safe read pattern:

```bash
dotenvx run -f /home/pi/.config/.env -- \
  op read "op://6jathgtxvuygms2t4xt4pjgooe/c76zdom3zpwl2l6fnc72oyc7ey/Access Token"
```

Rotation command pattern:

```bash
dotenvx run -f /home/pi/.config/.env -- \
  op read "op://6jathgtxvuygms2t4xt4pjgooe/c76zdom3zpwl2l6fnc72oyc7ey/Access Token" | \
python3 -c 'import sys
for line in sys.stdin.read().splitlines():
    if line.startswith("[dotenvx]") or line.startswith("⟐"):
        continue
    print(line)' | \
kubectl -n hermes-agent exec -i deployment/hermes-agent -c hermes-agent -- \
  sh -lc 'umask 077; token=/tmp/hermes-codex-app-token; cat > "$token"; \
  HERMES_HOME=/opt/data/profiles/codex /opt/hermes/.venv/bin/python - "$token" <<'"'"'PY'"'"'
from pathlib import Path
from datetime import datetime, timezone
import shutil, sys, uuid

from agent.credential_pool import (
    AUTH_TYPE_API_KEY,
    SOURCE_MANUAL,
    PooledCredential,
    load_pool,
)
from hermes_cli.auth import DEFAULT_CODEX_BASE_URL

profile = Path("/opt/data/profiles/codex")
backup_dir = (
    Path("/opt/data/backups/codex-token-import")
    / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
)
backup_dir.mkdir(parents=True, exist_ok=True)
auth_path = profile / "auth.json"
if auth_path.exists():
    shutil.copy2(auth_path, backup_dir / "auth.json")

token_path = Path(sys.argv[1])
token = token_path.read_text(encoding="utf-8").strip()
if not token or not token.startswith("at-"):
    raise SystemExit("token_invalid")

pool = load_pool("openai-codex")
pool._entries = [
    e for e in pool.entries()
    if not (e.provider == "openai-codex" and e.label == "codex-app-token")
]
pool.add_entry(PooledCredential(
    provider="openai-codex",
    id=uuid.uuid4().hex[:6],
    label="codex-app-token",
    auth_type=AUTH_TYPE_API_KEY,
    priority=0,
    source=f"{SOURCE_MANUAL}:dotenvx-1password",
    access_token=token,
    base_url=DEFAULT_CODEX_BASE_URL,
))
token_path.unlink(missing_ok=True)
print("backup_dir=" + str(backup_dir))
print("credential_label=codex-app-token")
PY'
```

Verification pattern:

```bash
kubectl -n hermes-agent exec deployment/hermes-agent -c hermes-agent -- \
  sh -lc 'HERMES_HOME=/opt/data/profiles/codex /opt/hermes/.venv/bin/python - <<'"'"'PY'"'"'
from agent.credential_pool import load_pool
from hermes_cli.models import provider_model_ids

pool = load_pool("openai-codex")
entries = pool.entries()
print("credential_count=" + str(len(entries)))
print("labels=" + ",".join(e.label for e in entries))
print("auth_types=" + ",".join(e.auth_type for e in entries))
models = provider_model_ids("openai-codex", force_refresh=True)
print("model_count=" + str(len(models)))
print("models_head=" + ",".join(models[:8]))
PY'
```

## Failure Handling

- If `op item edit` fails with `unsupported field type: ssoLogin`, stop retrying that approach and report that the item needs UI editing or a narrower CLI-safe update.
- If authentication fails, check only whether `/home/pi/.config/.env` contains the `OP_SERVICE_ACCOUNT_TOKEN` key and whether dotenvx can inject it. Do not print token contents.
- After three failures with the same approach, stop and report the attempts, concrete errors, and a different next approach.
