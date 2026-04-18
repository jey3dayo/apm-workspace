# Local APM packages

Store repo-owned local packages under `packages/<skill-id>/`.

Typical flow:

```bash
cd ~/.apm
mise install
mise run migrate -- apm-usage
mise run apply
```