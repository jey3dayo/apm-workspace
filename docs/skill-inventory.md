# Skill Inventory

スキル・MCP がどのレーンのどこにあるか。
どれを使うかの使い分けと検証中の競合スキルは [`skill-overlaps.md`](skill-overlaps.md)、残作業は `todo.txt` に置く。
個々の採用・撤去の理由と経緯は [`package-decisions.md`](package-decisions.md) を参照する。

## レーン一覧

全体像の図は [`diagrams/apm-skill-governance.html`](diagrams/apm-skill-governance.html)
（ローカルで開く。正本は隣の `.architecture.json`）。再生成は
`node ~/.claude/skills/archify/bin/archify.mjs deliver architecture <json> <html> --quality showcase`。

| レーン                 | 正本                                 | 配布                                                                                    | 用途                                                               |
| ---------------------- | ------------------------------------ | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| global（外部）         | root `apm.yml` の `dependencies.apm` | 全リポジトリへ自動 rollout                                                              | 横断的に使う外部スキル                                             |
| global（自作 catalog） | `catalog/skills/**`                  | 全リポジトリへ自動 rollout                                                              | 個人の横断ワークフロー                                             |
| ~/.apm 専用            | `.apm/skills/**`                     | この workspace 内の symlink bridge のみ                                                 | APM workspace 自身の運用手順                                       |
| optional               | `optional-skills/<id>/**`            | 利用リポジトリで個別 ref を直接 install                                                 | 選択リポジトリだけのワークフロー                                   |
| private                | `private-skills/.apm/skills/**`      | deploy で catalog と同時同期（fast path: `apply:skills:local`）・~/.apm では gitignored | マシンローカルの overlay（正本は private repo）                    |
| manual                 | `manual-skills/.apm/skills/**`       | 手動配置                                                                                | 通常レーンで壊れる upstream の受け皿（退役 upstream コピーを収容） |
| repo-local             | 各リポジトリの `apm.yml`             | そのリポジトリのみ                                                                      | ランタイム・認証・ブラウザに結び付くもの                           |

## global（外部スキル: root apm.yml）

グループは `apm.yml` の `# --- <group> ---` 見出しと同じ。

- org-restricted: `perman-aws-vault`
- review: `thermo-nuclear-code-quality-review`, `improve`（shadcn）
- engineering / writing: `natural-japanese`, `japanese-tech-writing`（gist、alias）, `yomiyasu`,
  mattpocock 系（`codebase-design`, `domain-modeling`, `grilling`,
  `improve-codebase-architecture`, `prototype`, `research`, `retro`, `setup-matt-pocock-skills`,
  `wait-what`, `wayfinder`, `writing-for-agents`）
- react: `react-doctor`, `react-best-practices`
- design: `frontend-design`, `agentation` / `agentation-self-driving`,
  emilkowalski 系（`apple-design`, `emil-design-eng`, `find-animation-opportunities`,
  `improve-animations`, `review-animations`）,
  ibelick 系（`baseline-ui`, `fixing-accessibility`, `fixing-metadata`,
  `fixing-motion-performance`, `improve-ui`）, `transitions-dev`, `ui-ux-pro-max`
- browser / analysis: `browser-harness`, `screenshot`, `archify`
- agent tools: `tuicr`, `agmsg`, `show-me`
- productivity / research: `i-have-adhd`, `last30days`

## global（自作 catalog: catalog/skills/）

- APM・環境運用: `apm-usage`（repo-local `apm.yml` の作成/整理は `references/repo-manifest.md`）,
  `mise`, `dotenvx`, `1password`, `herdr`, `tuxedo`
- 委譲・エージェント運用: `orchestrator-worker`, `agmsg-delegation`, `backlog-sweep`, `learning-intake`
- レビュー・品質: `review-fix-loop`, `polish`
- Git・出荷: `ship`, `atomic-commit`, `git-worktree`, `git-branch-cleanup`,
  `ci-stability-hooks`, `prepare-goal`
- リファクタリング・解析: `refactoring`, `similarity`, `cccc`
- ドキュメント・タスク: `docs-manager`, `docs-review`, `todo-changelog-ops`, `linear-task-ops`
- デザイン・ブラウザ: `design-md-workflow`, `pwa-layout`, `terminal-browser`
- リサーチ: `web-research`（計画・並列委譲・合成まで一体）

## ~/.apm 専用（.apm/skills/）

- `agent-curation` — catalog/agents と採用台帳の運用
- `skill-auditor` — スキル棚卸し
- `find-skills` — スキル探索
- `apm-deploy-verify` — catalog 変更後の deploy / 配布一致検証

## manual（manual-skills/）

- `gh-address-comments` — OpenAI 由来の退役 upstream コピー
- `gh-fix-ci` — OpenAI 由来の退役 upstream コピー

## optional（optional-skills/）

- `google-forms-survey-builder` — 利用例: `tech-talks`
- `slack-app-management` — Slack App を持つリポジトリのみ
- `premortem` — 実装前の失敗条件分析が必要なリポジトリのみ
- `scheduled-audit-ops` — 利用例: `ca-connect-site`（`docs/prompts/config.toml` を持つリポジトリのみ）
- `review-board` — UI レビューのレーン振り分けが要るリポジトリのみ

## private（private-skills/・~/.apm では gitignored、正本は private repo）

- `work-reports`, `work-log-maintenance`
  （社内情報を含むため private レーンへ移動。正本は github.com/jey3dayo/private-skills）

## repo-local / on-demand へ移管済み

- `ca-pass`, `mdb-api`, `notica-api`, `telma-api` — global から撤去済み。
  必要な利用リポジトリの `apm.yml` から `caad-develop/claude-code-marketplace`
  の各 `plugins/service-integrations/<id>` ref を個別導入する。

## repo-local で活用中

global の一覧に無くても廃止ではない。各リポジトリの `apm.yml` が正本（2026-10-02 時点の `ghq` 配下スキャン。パッケージ置き場の `our-apm` は除く）。

| ツール                                                                                    | 利用リポジトリ                                                                | 用途                                          |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------- |
| `agentation-mcp`（MCP）                                                                   | `ultra-rss-reader`                                                            | Agentation toolbar での UI アノテーション連携 |
| `agentation` / `agentation-self-driving`（benjitaylor, global dependency と併用）         | `caad-loca-bff`（両方）, `ultra-rss-reader`（`agentation-self-driving` のみ） | repo-local での Agentation 自動レビュー導線   |
| `tauri-mcp-server`（MCP）                                                                 | `ultra-rss-reader`                                                            | Tauri ランタイム検証                          |
| `terraform-style-guide` / `terraform-test`（hashicorp）                                   | `ca-connect-site`, `caad-asta`, `caad-terraform-infra`                        | Terraform 規約・テスト                        |
| `workers-best-practices` / `wrangler`（cloudflare）                                       | `keep-on`                                                                     | Cloudflare Workers                            |
| `perman-aws-vault` / `ca-pass` / `mdb-api` / `telma-api`（caad marketplace）              | `ca-connect-site`, `caad-asta`, `caad-loca-bff`                               | AWS 認証と社内 API 連携                       |
| `notica-api`（caad marketplace）                                                          | `ca-connect-site`                                                             | Notica API 連携                               |
| `mcp-server-patterns`, `chatgpt-apps`                                                     | `caad-loca-bff`                                                               | MCP / ChatGPT Apps 実装                       |
| `tauri`（EpicenterHQ）, `rust-best-practices`, `tauri-icon-gen`, `tauri-webview-geometry` | `ultra-rss-reader`                                                            | Tauri / Rust 実装                             |
| `marp-slide`, `slide-docs`, `google-forms-survey-builder`（optional）                     | `tech-talks`                                                                  | スライド制作・アンケート作成                  |
| `manga-rss-bridge`                                                                        | `manga-rss-bridge`, `homelab-k3s`                                             | プロジェクト固有運用                          |

## global MCP（root apm.yml の mcp:）

`context7`, `linear`, `mcp-simple-voicevox`

`mise run check` の `lint:skill-inventory` が上記一覧と `apm.yml` の `dependencies.mcp` を照合する。Cursor user-scope（`~/.cursor/mcp.json`）は APM 外 — [`package-decisions.md`](package-decisions.md) の Cursor 節。

## メンテナンス

- 更新タイミング: レーン間の移動、global への追加・撤去、repo-local の新規採用時
- root `apm.yml` の `mcp:` を変えたら global MCP 節の backtick 行を同じ集合に更新する（`lint:skill-inventory` が `mise run check` で検証）
- 外部スキルの dependency を追加・撤去したら `## global（外部スキル: root apm.yml）` の一覧を更新する（`lint:skill-inventory` が `apm.lock.yaml` と照合する）
- global から repo-local / optional への移管: `apm-usage` の Install Gate と Fast Path 9 に従う
- repo-local の再スキャン: `ghq list -p` で各リポジトリの `apm.yml` を確認
