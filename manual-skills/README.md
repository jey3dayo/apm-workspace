# manual-skills

This directory contains copied skills that are kept outside the default managed APM lane.

- Use this package for skills that APM does not manage cleanly from upstream
- Typical reasons: symlinks, packaging quirks, or upstream layouts that break normal managed rollout
- Author copied skills under `manual-skills/.apm/skills/**`
- Do not add this package to the root `apm.yml`
- Distribute it explicitly when needed, for example with `jey3dayo/apm-workspace/manual-skills`
- Keep provenance and migration notes in `manual-skills/upstreams/**`
- Re-check upstream compatibility with `apm >= 0.9.1` before deciding a copied skill must stay here permanently
