# APM Task Coverage

現状の `~/.config/nix` 由来の配布から `~/.apm` ベース運用へ移した範囲を、task 観点で整理したメモです。

## Migration Status

| 対象 | 今の正本 | APM task で配布できるか | 補足 |
| --- | --- | --- | --- |
| `skills` | `~/.config/agents/src/skills/**` | できる | `catalog/.apm/skills/**` に stage され、`catalog#main` から配布 |
| `agents` | `~/.config/agents/src/agents/**` | できる | `catalog/agents/**` に入り runtime sync 対象 |
| top-level `commands/` | `~/.config/agents/src/commands/**` | できる | `catalog/commands/**` に入り runtime sync 対象 |
| `rules` | `~/.config/agents/src/rules/**` | できる | `catalog/rules/**` に入り runtime sync 対象 |
| `AGENTS.md` | `~/.config/agents/src/AGENTS.md` | できる | tracked catalog の instructions として配布 |
| external skills | upstream repo | できる | `migrate-external` で `apm.yml` に ref 登録 |

## Task Coverage

| task / command | skills | agents | rules | `AGENTS.md` | commands | 役割 |
| --- | --- | --- | --- | --- | --- | --- |
| `mise run apply` | ○ | ○ | ○ | ○ | ○ | global install 実行後に tracked `AGENTS.md` / `agents/` / `commands/` / `rules/` を runtime sync |
| `mise run update` | ○ | ○ | ○ | ○ | ○ | checkout 更新 + deps update + apply 相当 |
| `mise run doctor` | 状態確認 | 状態確認 | 状態確認 | 状態確認 | 状態確認 | target presence, overlap, catalog health を確認 |
| `mise run format` | 間接 | 間接 | 間接 | 間接 | 間接 | workspace の Markdown / TOML / YAML を整形 |
| `mise run ci:check` | ○ | ○ | ○ | ○ | ○ | format check + validate + validate-catalog + smoke-catalog |
| `mise run ci` | ○ | ○ | ○ | ○ | ○ | format → validation → apply → doctor でローカル配布まで実行 |
| `mise run stage-catalog` | ○ | ○ | ○ | ○ | ○ | authoring source から tracked catalog を再生成 |
| `mise run catalog:tidy` | ○ | ○ | ○ | ○ | ○ | stage-catalog → validate-catalog → doctor の整理導線 |
| `mise run register-catalog` | ○ | ○ | ○ | ○ | ○ | push 済みの `catalog` ref を install |
| `mise run smoke-catalog` | ○ | ○ | ○ | ○ | ○ | temp install による smoke test |
| `mise run migrate-external` | external skillsのみ | × | × | × | × | `nix/agent-skills-sources.nix` から external ref を manifest へ登録 |
| `mise run list` | 依存一覧 | 依存一覧 | 依存一覧 | 依存一覧 | 依存一覧 | global dependency list を表示 |
| `mise run validate-catalog` | ○ | ○ | ○ | ○ | ○ | drift check 用の公開 task |

## Notes

- `register-catalog` は local diff をそのまま配る command ではなく、commit / push 済みの `catalog` を install する flow。
- `validate-catalog` は `mise.toml` からも叩けるが、実体は workspace script 側の validation command。
- top-level `commands/` も managed catalog に移管済みなので、編集は `~/.config/agents/src/commands/` を起点に行う。

## Current Remaining Tasks

2026-04-20 時点で残っている実務上のタスクは次です。

1. `.config` 側の APM 変更を commit / push する
   - 対象は `scripts/apm-workspace.ps1|.sh`、`agents/src/commands/`、`agents/src/skills/apm-usage/`、`docs/tools/apm-workspace.md` など
2. `.apm` 側の workspace / tracked catalog 変更を commit / push する
   - 対象は `catalog/commands/`、staged `apm-usage`、`docs/apm-task-coverage.md`、`README.md`、`llms.md`、`TODO.md` など
3. `catalog/` を push したあとで `mise run register-catalog` を実行する
   - `catalog#main` の upstream ref で再配布し、workspace install state を最新化する

それ以外の「commands を catalog に入れる」作業自体は完了扱いでよいです。
