# trailofbits-skills

- Upstream: `trailofbits/skills`
- Managed here as a curated local copy for APM rollout
- Why here:
  - upstream link syntax still causes APM compile warnings under APM 0.9.3
  - `agentic-actions-auditor` misses `{baseDir}/references/**` during compile
  - `sharp-edges` misses anchored `references/config-patterns.md` links during compile
  - `sarif-parsing` misses `{baseDir}/resources/**` during compile
  - local copies let us normalize references without forking the whole repo immediately
- Current curated skills:
  - `agentic-actions-auditor`
  - `sharp-edges`
  - `sarif-parsing`
- Candidate destination:
  - move back to external refs if APM link resolution or upstream layout becomes compatible
