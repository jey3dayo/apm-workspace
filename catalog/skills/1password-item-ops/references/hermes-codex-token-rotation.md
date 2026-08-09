# Hermes Codex App Token Rotation

Rotate the homelab Hermes Agent Codex app token from 1Password into the Kubernetes Pod.

## Source of truth

- Vault: `Automation` (`6jathgtxvuygms2t4xt4pjgooe`)
- Item: `Codex Access Token` (`c76zdom3zpwl2l6fnc72oyc7ey`)
- Secret field: `Access Token`
- Hermes profile: `/opt/data/profiles/codex`
- Bootstrap token: `/home/pi/.config/.env` holds `OP_SERVICE_ACCOUNT_TOKEN` as an `encrypted:` dotenvx value.

## Rules

- Treat 1Password as the source of truth.
- Never write the token to the repository, shell history, or logs.
- Prefer item and vault IDs over names for automation.
- Pipe the secret through stdin directly into the Pod.
- Back up `/opt/data/profiles/codex/auth.json` before replacing the `openai-codex` credential.
- Verify only non-secret metadata: credential label, auth type, model count, and model names.
- The app token is not a refresh-token OAuth session. If it expires, update the 1Password item and run the rotation again.

## Safe read pattern

```bash
dotenvx run -f /home/pi/.config/.env -- \
  op read "op://6jathgtxvuygms2t4xt4pjgooe/c76zdom3zpwl2l6fnc72oyc7ey/Access Token"
```

## Rotation command pattern

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

## Verification pattern

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
