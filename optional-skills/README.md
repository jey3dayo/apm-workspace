# optional-skills

This directory contains individually installable skills that are tracked in the
APM workspace but are not installed by the global rollout. The collection root
is not an APM package.

- Author optional workspace-owned skills under `optional-skills/<id>/`.
- Add only `jey3dayo/apm-workspace/optional-skills/<id>#main` to a repository's own
  `apm.yml` when that repository needs the skill.
- Do not add the `optional-skills` collection root to the global `~/.apm/apm.yml`.

Example:

```bash
apm install jey3dayo/apm-workspace/optional-skills/google-forms-survey-builder#main
```

For the workspace-owned Slack app guidance, use:

```bash
apm install jey3dayo/apm-workspace/optional-skills/slack-app-management#main
```

External bundles that contain optional sub-skills should remain external
dependencies. For example, install `banner-design` in a repository that needs
it with:

```bash
apm install nextlevelbuilder/ui-ux-pro-max-skill \
  --skill banner-design
```
