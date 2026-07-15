# optional-skills

This package contains skills that are tracked in the APM workspace but are not
installed by the global rollout.

- Author optional workspace-owned skills under `optional-skills/.apm/skills/<id>/`.
- Add `jey3dayo/apm-workspace/optional-skills#main` to a repository's own
  `apm.yml` when that repository needs one of these skills.
- Install only the requested skill with `apm install --skill <id>`.
- Do not add this package to the global `~/.apm/apm.yml` unless every project
  should receive the package.

Example:

```bash
apm install jey3dayo/apm-workspace/optional-skills#main \
  --skill google-forms-survey-builder
```

For the workspace-owned Slack app guidance, use:

```bash
apm install jey3dayo/apm-workspace/optional-skills#main \
  --skill slack-app-management
```

External bundles that contain optional sub-skills should remain external
dependencies. For example, install `banner-design` in a repository that needs
it with:

```bash
apm install nextlevelbuilder/ui-ux-pro-max-skill \
  --skill banner-design
```
