# Folder Policy

Use this guide when choosing where a personal skill should live in the CAAD marketplace.

## Categories

| Category          | Destination                       | Use for                                                                                                                                  |
| ----------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Development tools | `plugins/dev-tools/<skill-name>/` | Code quality, review, CI, implementation workflow, refactoring, TypeScript/JavaScript/Rust/Go guidance, task-to-PR style automation      |
| Infrastructure    | `plugins/infra/<skill-name>/`     | AWS, cloud, authentication, identity, network, internal platform APIs, deployment credentials, operational runbooks                      |
| Documentation     | `plugins/docs/<skill-name>/`      | Markdown writing, diagrams, slide decks, document generation, presentation workflows                                                     |
| Utilities         | `plugins/utils/<skill-name>/`     | General CLI helpers, environment utilities, marketplace operations, debug helpers, tool setup that is not tied to one engineering domain |
| Samples           | `plugins/samples/<skill-name>/`   | Examples, demos, templates, learning-only plugins                                                                                        |

## Tie Breakers

- Prefer `dev-tools` when the skill changes how engineers build, test, review, or ship code.
- Prefer `infra` when the skill touches credentials, cloud accounts, deployment targets, identity providers, or internal service APIs.
- Prefer `docs` only when the main output is documentation or presentation material.
- Prefer `utils` for repository maintenance or tool operations that are useful across domains.
- Use `samples` only when the skill is intentionally non-production or educational.

## Plugin Shape

Use one skill per plugin unless the user explicitly asks to publish a bundle. The default shape is:

```text
plugins/{category}/{skill-name}/
├── .claude-plugin/plugin.json
└── skills/
    └── {skill-name}/
        └── SKILL.md
```

Keep copied resources under the skill folder. Marketplace installs copy plugin contents into a cache, so files must not depend on paths outside the plugin directory.
