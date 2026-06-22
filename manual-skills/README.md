# manual-skills

This directory contains copied skills that are kept outside the default managed APM lane.

Current state: this package is intentionally empty. Keep the package scaffold so
future upstream skills can be routed here when the normal managed lane is not
compatible.

- Use this package for skills that APM does not manage cleanly from upstream
- Typical reasons: symlinks, packaging quirks, or upstream layouts that break normal managed rollout
- Author copied skills under `manual-skills/.apm/skills/**`
- Add this package to the root `apm.yml` when a copied skill must ship in the default global rollout
- Root manifest ref: `jey3dayo/apm-workspace/manual-skills`
- Keep provenance and migration notes in `manual-skills/upstreams/**`
- Re-check upstream compatibility before deciding a copied skill must stay here permanently
