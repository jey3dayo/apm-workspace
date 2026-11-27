# Skill Inventory

スキルや MCP をどのレーンのどこに配置しているかをまとめています。
役割の近いスキルの使い分けや検証中の競合スキルは [`skill-overlaps.md`](skill-overlaps.md) に、残作業は [`todo.txt`](../todo.txt) に置いています。
個々の採用・撤去の理由と経緯は [`package-decisions.md`](package-decisions.md) を参照してください。

## レーン一覧

| レーン                 | 管理元                               | 配布                                                                                       | 用途                                                       |
| ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| global（外部）         | root `apm.yml` の `dependencies.apm` | 全リポジトリへ自動 rollout                                                                 | 横断的に使う外部スキル                                     |
| global（自作 catalog） | `catalog/.apm/skills/**`             | 全リポジトリへ自動 rollout                                                                 | 個人の横断ワークフロー                                     |
| workspace 専用         | `.apm/skills/**`                     | この workspace 内の symlink bridge のみ                                                    | APM workspace 自身の運用手順                               |
| optional               | `optional-skills/<id>/**`            | 利用リポジトリで個別 ref を直接 install                                                    | 選択したリポジトリだけで使うワークフロー                   |
| private                | `private-skills/.apm/skills/**`      | native 配布の対象外。consumer の `~/.apm/skills/` に配置し、この workspace では gitignored | マシンローカルの overlay（管理元は private repo）          |
| manual                 | `manual-skills/.apm/skills/**`       | `manual-skills` package を native 配布                                                     | 通常レーンで扱えない upstream の受け皿（退役コピーを含む） |
| repo-local             | 各リポジトリの `apm.yml`             | そのリポジトリのみ                                                                         | ランタイム・認証・ブラウザに結び付くもの                   |

## global の一覧

global の外部スキルと MCP は root `apm.yml`（`dependencies.apm` / `dependencies.mcp`）と `apm.lock.yaml` で、自作 catalog スキルは `catalog/.apm/skills/` で直接確認します。このファイルには名前を転記しません。

Cursor の user-scope MCP（`~/.cursor/mcp.json`）は APM 管理外です。詳細は [`package-decisions.md`](package-decisions.md) の「Cursor user-scope MCP (`~/.cursor/mcp.json`)」を参照してください。

## workspace 専用（`.apm/skills/`）

- `agent-curation`: `catalog/.apm/agents` と採用記録の運用
- `skill-auditor`: スキル棚卸し
- `find-skills`: スキル探索

## manual（`manual-skills/`）

- `gh-address-comments`: OpenAI 由来の退役 upstream コピー
- `gh-fix-ci`: OpenAI 由来の退役 upstream コピー
- `explain-before-shorten`: Zenn 記事の `SKILL.md` を原文のまま手動管理

## optional（`optional-skills/`）

- `google-forms-survey-builder`: 利用例 `tech-talks`
- `slack-app-management`: Slack App を持つリポジトリのみ
- `scheduled-audit-ops`: 利用例 `work-site`（`docs/prompts/config.toml` を持つリポジトリのみ）
- `review-board`: UI レビューのレーン振り分けが必要なリポジトリのみ
- `drawio`: draw.io 図を管理するリポジトリのみ

## private（`private-skills/`）

この workspace では gitignored で、管理元は `github.com/jey3dayo/private-skills` です。

- `work-reports`, `work-log-maintenance`: 社内情報を含むため private レーンへ移動しました。

## repo-local / on-demand へ移管済み

- `internal-api-a`, `internal-api-b`, `internal-api-c`, `internal-api-d`: global から撤去済みです。必要な利用リポジトリの `apm.yml` から、`<work-marketplace>` の各 `plugins/service-integrations/<id>` ref を個別導入します。実際の repo 名と id は会社マーケットプレイスのプラグイン一覧で確認します。
- `aws-credential-helper`: 2026-10-19 に global APM から撤去済みです。Claude Code・Codex・Grok 共通で会社マーケットのプラグインとして管理しており、APM の `apm.yml` には載せません。

## repo-local / on-demand

global の一覧にないことは廃止を意味しません。repo-local の採用状態は各リポジトリの `apm.yml` が管理元なので、必要なときに `ghq list -p` で対象リポジトリを探して確認します。一覧の複製は置きません。

## 更新ルール

- 更新タイミング: レーンの追加・変更、optional / manual / private の出入り、repo-local の新規採用・撤去時に更新します。global の追加・撤去だけなら、このファイルは触りません。
- global から repo-local / optional への移管: `apm-usage` の Install Gate と Fast Path 9 に従います。
- repo-local の採用状態: 各リポジトリの `apm.yml` を確認します。
