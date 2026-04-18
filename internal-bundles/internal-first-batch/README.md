# internal-first-batch Bundle

This bundle is generated from ~/.config internal bundled skills for the global APM migration pilot.

- Source inventory: `~/.config/agents/src/internal-apm-first-batch.txt`
- Source skills: `~/.config/agents/src/skills/<id>/`
- Purpose: provide a valid APM package artifact for future publish/install work
- Current limitation: `apm install -g <local-path>` is rejected by APM 0.8.11 at user scope, so this bundle is for validation and publication prep only
