# Skill Inventory

スキル・MCP がどのレーンのどこにあるか。
どれを使うかの使い分けと検証中の競合スキルは [`skill-overlaps.md`](skill-overlaps.md)、残作業は `todo.txt` に置く。
個々の採用・撤去の理由と経緯は [`package-decisions.md`](package-decisions.md) を参照する。

## レーン一覧

| レーン                 | 正本                                 | 配布                                                                                       | 用途                                                               |
| ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| global（外部）         | root `apm.yml` の `dependencies.apm` | 全リポジトリへ自動 rollout                                                                 | 横断的に使う外部スキル                                             |
| global（自作 catalog） | `catalog/.apm/skills/**`             | 全リポジトリへ自動 rollout                                                                 | 個人の横断ワークフロー                                             |
| workspace 専用         | `.apm/skills/**`                     | この workspace 内の symlink bridge のみ                                                    | APM workspace 自身の運用手順                                       |
| optional               | `optional-skills/<id>/**`            | 利用リポジトリで個別 ref を直接 install                                                    | 選択リポジトリだけのワークフロー                                   |
| private                | `private-skills/.apm/skills/**`      | native 配布の対象外（consumer の `~/.apm/skills/` に置く）・この workspace では gitignored | マシンローカルの overlay（正本は private repo）                    |
| manual                 | `manual-skills/.apm/skills/**`       | 手動配置                                                                                   | 通常レーンで壊れる upstream の受け皿（退役 upstream コピーを収容） |
| repo-local             | 各リポジトリの `apm.yml`             | そのリポジトリのみ                                                                         | ランタイム・認証・ブラウザに結び付くもの                           |

## global の一覧

global の外部スキルと MCP は root `apm.yml`（`dependencies.apm` / `dependencies.mcp`）と `apm.lock.yaml`、自作 catalog スキルは `catalog/.apm/skills/` を正本として直接見る。このファイルには名前を写さない。
Cursor user-scope（`~/.cursor/mcp.json`）は APM 外 — [`package-decisions.md`](package-decisions.md) の Cursor 節。

## workspace 専用（.apm/skills/）

- `agent-curation` — catalog/.apm/agents と採用台帳の運用
- `skill-auditor` — スキル棚卸し
- `find-skills` — スキル探索

## manual（manual-skills/）

- `gh-address-comments` — OpenAI 由来の退役 upstream コピー
- `gh-fix-ci` — OpenAI 由来の退役 upstream コピー
- `explain-before-shorten` — Zenn 記事の SKILL.md を原文のまま手動管理

## optional（optional-skills/）

- `google-forms-survey-builder` — 利用例: `tech-talks`
- `slack-app-management` — Slack App を持つリポジトリのみ
- `premortem` — 実装前の失敗条件分析が必要なリポジトリのみ
- `scheduled-audit-ops` — 利用例: `work-site`（`docs/prompts/config.toml` を持つリポジトリのみ）
- `review-board` — UI レビューのレーン振り分けが要るリポジトリのみ
- `drawio` — draw.io 図を管理するリポジトリのみ

## private（private-skills/・この workspace では gitignored、正本は private repo）

- `work-reports`, `work-log-maintenance`
  （社内情報を含むため private レーンへ移動。正本は github.com/jey3dayo/private-skills）

## repo-local / on-demand へ移管済み

- `internal-api-a`, `internal-api-b`, `internal-api-c`, `internal-api-d` — global から撤去済み。
  必要な利用リポジトリの `apm.yml` から `<work-marketplace>`
  の各 `plugins/service-integrations/<id>` ref を個別導入する（実際の repo と id は会社マーケットプレイスのプラグイン一覧で確認する）。
- `aws-credential-helper` — global APM から撤去済み（2026-10-19）。会社マーケットのプラグインで管理（Claude Code / Codex / Grok 共通）。APM の `apm.yml` には載せない。

## repo-local / on-demand

global の一覧に無いことは廃止を意味しない。repo-local の採用状態は各リポジトリの `apm.yml` が正本なので、必要なときに `ghq list -p` で対象リポジトリを探して確認する。一覧の複製は置かない。

## メンテナンス

- 更新タイミング: レーンの追加・変更、optional / manual / private の出入り、repo-local の新規採用・撤去時（global の追加・撤去だけならこのファイルは触らない）
- global から repo-local / optional への移管: `apm-usage` の Install Gate と Fast Path 9 に従う
- repo-local の採用状態: 各リポジトリの `apm.yml` を確認
