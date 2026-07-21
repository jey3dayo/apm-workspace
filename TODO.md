# TODO

## Open Tasks

- Optional: run `apm prune` to drop the ~14 orphaned package cache entries not declared in `apm.yml`.
- Review and execute the candidates in [`docs/skill-inventory.md`](docs/skill-inventory.md) の「移管候補（未実施）」
  (Agentation は repo-local 移管済み。残りは browser 系・understand 系・社内 API 系).
- Before removing any candidate from the global manifest, verify it in a concrete consuming repository
  with a repo-local `apm.yml` and record the result in [`docs/package-decisions.md`](docs/package-decisions.md).

## Global / Repo-local Skill Strategy (2026-07-15)

### 基本方針

- Global は「複数リポジトリで常時使う基盤」に絞る。
- 案件・フレームワーク・UI・特定サービスに依存するスキルは、catalog に保存できる場合でも global 配布しない。
- APM 管理の external skill は upstream を正本とし、個別リポジトリの `apm.yml` から必要な skill だけを選択する。
- `catalog` は全員向けの管理対象、`optional-skills/<id>` は明示的に opt-in する単体スキル、`apm.yml` は依存の宣言として責務を分ける。

### Global に残すもの

- APM の運用・検証・配布、共通の安全性・品質確認。
- リポジトリをまたいで使う調査・環境操作・Git workflow の基盤。
- 個人の開発環境に常時必要で、起動時に持っていても用途がぶれないもの。

### Repo-local へ移す候補

- `[x]` `google-forms-survey-builder`: Google Forms 案件専用。`optional-skills` に移管済み。
- `[x]` `slack-app-management`: Slack アプリ案件専用。`optional-skills` に移管済み。
- `[x]` `premortem`: 実装前の失敗条件分析が必要なリポジトリだけで使うため、`optional-skills` に移管済み。
- `[x]` Agentation: `caad-loca-bff` / `ultra-rss-reader` の repo-local へ移管済み（2026-07-16）。
- `[x]` UI bundle: `ui-ux-pro-max` 本体のみ global 維持に縮小済み（2026-07-16）。React/UI validation 系は棚卸しの結果 global 維持を決定。
- `[ ]` browser automation（`browser-harness` / `agent-browser`）: 対象リポジトリで利用実績を確認して段階移管。
- `[ ]` `ca-pass`、`mdb-api`、`notica-api`、`telma-api`: catalog の個人スキルではなく、外部 marketplace plugin。コピーせず upstream 参照を利用者側の `apm.yml` に置く。

### 社員向けスキル検索の設計メモ

Global から専門スキルを外すために、軽量な「スキル検索・導入入口」だけを global に残す案を採用する。

- 検索インデックスは `catalog/**`、`optional-skills/**`、root `apm.yml` / `apm.lock.yaml` の external 依存を統合する。
- 検索結果には skill id、用途、scope、source kind、upstream / package ref、trust・license 情報、導入コマンド、現在の global 配布状態を表示する。
- 導入先リポジトリで `apm.yml` を更新する。workspace-owned optional は単体 ref、external bundle は必要な場合だけ `--skill <id>` を使い、global へ直接追加しない。
- `find-skills` は検索体験・候補説明・導入導線の参考にする。ただし現状は skills.sh / `npx skills` 向けで、社内 catalog、optional skill collection、APM の scope 判定は扱わない。
- したがって、既存 `find-skills` を global の専門スキル配布に流用するのではなく、APM-aware な index / CLI を別途設計する。global にはその検索入口だけを残す。

### Global から外すゲート

1. 利用候補の consuming repository を1つ以上特定する。
2. その repository の repo-local `apm.yml` に追加し、対象 skill の導入と実タスクを確認する。
3. global manifest から削除して `mise run deploy` を実行し、global target に残っていないことを確認する。
4. `docs/package-decisions.md` に移管理由、導入先、検証結果、戻し方を記録する。
5. 失敗時は global に戻すのではなく、まず repo-local package の不足や依存条件を修正する。

### 次の実行順

- `[ ]` Agentation / browser automation の利用リポジトリを特定する。
- `[ ]` React/UI validation を利用するリポジトリで repo-local install を検証する。
- `[ ]` 社員向け検索 index の最小仕様と `apm search` 相当の read-only CLI を設計する。
- `[x]` flat optional skill を GitHub に公開し、`tech-talks` を `optional-skills/google-forms-survey-builder#main` の単体 ref へ移して lock / deploy を確定した。

## Notes

- `skills`, `agents`, `commands`, `rules`, and `AGENTS.md` now use `~/.apm/catalog/**` as the managed source of truth.
- `~/.config/nix/agent-skills-sources.nix` is now intentionally empty because external skill sources were retired.
- The current coverage table lives in `docs/apm-task-coverage.md`.
- `nextlevelbuilder/ui-ux-pro-max-skill/.claude/skills/ui-ux-pro-max` は subdir install だと `scripts/` などの相対参照が壊れるため、managed skill 化で扱う。
- Verified on 2026-04-20 with `validate-catalog`, `doctor`, `ci:check`, `apply`, `bash -n`, and `Invoke-Pester` while `~/.config/agents` was absent.
- `.config` still has unrelated pre-existing changes, but they are outside this APM migration slice.
