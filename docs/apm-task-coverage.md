# APM Task Coverage

現状の `~/.config/nix` 由来の配布から `~/.apm` ベース運用へ移した範囲を、task 観点で整理したメモです。

## Migration Status

| 対象                  | 今の正本                     | APM task で配布できるか | 補足                                       |
| --------------------- | ---------------------------- | ----------------------- | ------------------------------------------ |
| `skills`              | `~/.apm/catalog/skills/**`   | できる                  | personal skills の authoring source        |
| `agents`              | `~/.apm/catalog/agents/**`   | できる                  | runtime sync 対象                          |
| top-level `commands/` | `~/.apm/catalog/commands/**` | できる                  | runtime sync 対象                          |
| `rules`               | `~/.apm/catalog/rules/**`    | できる                  | runtime sync 対象                          |
| `AGENTS.md`           | `~/.apm/catalog/AGENTS.md`   | できる                  | managed catalog の instructions として配布 |

## Task Coverage

| task / command              | skills   | agents   | rules    | `AGENTS.md` | commands | 役割                                                                                             |
| --------------------------- | -------- | -------- | -------- | ----------- | -------- | ------------------------------------------------------------------------------------------------ |
| `mise run apply`            | ○        | ○        | ○        | ○           | ○        | global install 実行後に managed `AGENTS.md` / `agents/` / `commands/` / `rules/` を runtime sync |
| `mise run update`           | ○        | ○        | ○        | ○           | ○        | checkout 更新 + deps update + apply 相当                                                         |
| `mise run doctor`           | 状態確認 | 状態確認 | 状態確認 | 状態確認    | 状態確認 | target presence, overlap, catalog health を確認                                                  |
| `mise run format`           | 間接     | 間接     | 間接     | 間接        | 間接     | workspace の Markdown / TOML / YAML を整形                                                       |
| `mise run ci:check`         | ○        | ○        | ○        | ○           | ○        | format check + validate + validate:catalog + smoke-catalog                                       |
| `mise run ci`               | ○        | ○        | ○        | ○           | ○        | format → validation → apply → doctor でローカル配布まで実行                                      |
| `mise run stage-catalog`    | ○        | ○        | ○        | ○           | ○        | `catalog/` を正規化して managed catalog package を整える                                         |
| `mise run catalog:tidy`     | ○        | ○        | ○        | ○           | ○        | stage-catalog → validate:catalog → doctor の整理導線                                             |
| `mise run register-catalog` | ○        | ○        | ○        | ○           | ○        | push 済みの `catalog` ref を install                                                             |
| `mise run smoke-catalog`    | ○        | ○        | ○        | ○           | ○        | temp install による smoke test                                                                   |
| `mise run validate:catalog` | ○        | ○        | ○        | ○           | ○        | drift check 用の公開 task                                                                        |

## Notes

- `register-catalog` は local diff をそのまま配る command ではなく、commit / push 済みの `catalog` を install する flow。
- `validate:catalog` は `mise.toml` からも叩けるが、実体は workspace script 側の validation command。
- 新しい personal skill は `~/.apm/catalog/skills/<id>/` に作る。runtime targets を起点にしない。
- 新しい skill の作成や移管は `skill-creator` を使い、manifest や配布モデル全体の判断は `apm-usage` で補う。

## Current Remaining Tasks

2026-04-20 時点で、この migration slice の必須残件はありません。

- follow-up として、helper docs や prompts に残る旧 authoring 指示の掃除は継続候補
