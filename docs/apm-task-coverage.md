# APM Task Coverage

現状の `~/.config/nix` 由来の配布から `~/.apm` ベース運用へ移した範囲を、task 観点で整理したメモです。

## Migration Status

| 対象 | 今の正本 | APM task で配布できるか | 補足 |
| --- | --- | --- | --- |
| `skills` | `~/.config/agents/src/skills/**` | できる | `catalog/.apm/skills/**` に stage され、`catalog#main` から配布 |
| `agents` | `~/.config/agents/src/agents/**` | できる | `catalog/agents/**` に入り runtime sync 対象 |
| `rules` | `~/.config/agents/src/rules/**` | できる | `catalog/rules/**` に入り runtime sync 対象 |
| `AGENTS.md` | `~/.config/agents/src/AGENTS.md` | できる | tracked catalog の instructions として配布 |
| top-level `commands/` | 未定義 | できない | `agents/src` に authoritative な `commands/` tree がまだ無い |
| external skills | upstream repo | できる | `migrate-external` で `apm.yml` に ref 登録 |

## Task Coverage

| task / command | skills | agents | rules | `AGENTS.md` | commands | 役割 |
| --- | --- | --- | --- | --- | --- | --- |
| `mise run apply` | ○ | ○ | ○ | ○ | × | global install 実行後に tracked `AGENTS.md` / `agents/` / `rules/` を runtime sync |
| `mise run update` | ○ | ○ | ○ | ○ | × | checkout 更新 + deps update + apply 相当 |
| `mise run doctor` | 状態確認 | 状態確認 | 状態確認 | 状態確認 | × | target presence, overlap, catalog health を確認 |
| `mise run stage-catalog` | ○ | ○ | ○ | ○ | × | authoring source から tracked catalog を再生成 |
| `mise run register-catalog` | ○ | ○ | ○ | ○ | × | push 済みの `catalog` ref を install |
| `mise run smoke-catalog` | ○ | ○ | ○ | ○ | × | temp install による smoke test |
| `mise run migrate-external` | external skillsのみ | × | × | × | × | `nix/agent-skills-sources.nix` から external ref を manifest へ登録 |
| `mise run list` | 依存一覧 | 依存一覧 | 依存一覧 | 依存一覧 | × | global dependency list を表示 |
| `powershell ... apm-workspace.ps1 validate-catalog` | ○ | ○ | ○ | ○ | × | drift check 用の maintenance command |

## Notes

- `register-catalog` は local diff をそのまま配る command ではなく、commit / push 済みの `catalog` を install する flow。
- `validate-catalog` は現状 `mise.toml` の task ではなく、workspace script 側の maintenance command。
- `commands/` を APM 対象に入れるなら、先に `~/.config/agents/src/commands/` を正本として定義する必要がある。
