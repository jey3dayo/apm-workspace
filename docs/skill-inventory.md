# Skill Inventory

スキル・MCP の配置レーン別の集約一覧（2026-07-16 時点）。
「どこに何があるか」だけをここに置き、採用・撤去の理由は
[`package-decisions.md`](package-decisions.md)、移管の判断基準は
[`skill-scope-proposals.md`](skill-scope-proposals.md) を参照する。

## レーン一覧

| レーン                 | 正本                                 | 配布                                        | 用途                                           |
| ---------------------- | ------------------------------------ | ------------------------------------------- | ---------------------------------------------- |
| global（外部）         | root `apm.yml` の `dependencies.apm` | 全リポジトリへ自動 rollout                  | 横断的に使う外部スキル                         |
| global（自作 catalog） | `catalog/skills/**`                  | 全リポジトリへ自動 rollout                  | 個人の横断ワークフロー                         |
| ~/.apm 専用            | `.apm/skills/**`                     | この workspace 内の symlink bridge のみ     | APM workspace 自身の運用手順                   |
| optional               | `optional-skills/.apm/skills/**`     | 利用リポジトリで `apm install --skill <id>` | 選択リポジトリだけのワークフロー               |
| private                | `private-skills/.apm/skills/**`      | ローカル Codex sync のみ・未追跡            | マシンローカルの overlay                       |
| manual                 | `manual-skills/.apm/skills/**`       | 手動配置                                    | 通常レーンで壊れる upstream の受け皿（現在空） |
| repo-local             | 各リポジトリの `apm.yml`             | そのリポジトリのみ                          | ランタイム・認証・ブラウザに結び付くもの       |

## global（外部スキル: root apm.yml）

- デザイン・UI/UX: `frontend-design`, `ui-ux-pro-max`, `baseline-ui`,
  `fixing-accessibility`, `fixing-metadata`, `fixing-motion-performance`,
  `make-interfaces-feel-better`, `transitions-dev`, `web-design-guidelines`
- モーション（emilkowalski/skills）: `emil-design-eng`, `review-animations`,
  `improve-animations`, `animation-vocabulary`
- レビュー・監査: `hunk-review`, `thermo-nuclear-code-quality-review`,
  `improve`（shadcn）, `react-doctor`
- React / Web 実装: `composition-patterns`, `react-best-practices`,
  `browser-harness`, `agent-browser`, `screenshot`
- ワークフロー（obra/superpowers）: brainstorming, executing-plans,
  systematic-debugging, TDD, worktrees, verification ほか計 11
- Codex 連携（openai）: `codex-cli-runtime`, `codex-result-handling`,
  `gpt-5-4-prompting`, `gh-address-comments`, `gh-fix-ci`
- 社内（caad-develop）: `perman-aws-vault`, `ca-pass`, `notica-api`,
  `mdb-api`, `telma-api`, `caad-skill-deployer`
- その他: `understand` / `understand-dashboard`, `humanizer-ja`,
  `web-research`, mattpocock 系 5, `empirical-prompt-tuning`

## global（自作 catalog: catalog/skills/）

36 スキル。主な系統:

- APM・環境運用: `apm-usage`, `apm-repo-bootstrap`, `mise`, `mcp-tools`,
  `headroom`, `rtk`, `dotenvx-env-ops`, `1password-item-ops`, `herdr`
- レビュー・品質: `code-review`, `review-board`, `review-fix-loop`,
  `review-plan`, `polish`, `code-quality-improvement`, `predictive-analysis`,
  `premortem`, `quiet-command-auditor`
- デザイン: `design-md-workflow`, `design-system-review`
- リファクタリング・解析: `refactoring`, `similarity`, `tsr`
- ドキュメント: `docs-manager`, `docs-entrypoint-review`,
  `architecture-boundary-docs`, `japanese-tech-writing`, `rules-creator`
- Git・作業運用: `atomic-commit`, `git-worktree`, `ci-stability-hooks`,
  `work-log-maintenance`, `prepare-goal`
- リサーチ: `jina-web-research`, `cross-research`
- ランタイム資産: `codex-companion-scripts`

## ~/.apm 専用（.apm/skills/）

- `agent-curation` — catalog/agents と採用台帳の運用
- `skill-auditor` — スキル棚卸し
- `find-skills` — スキル探索

## optional（optional-skills/）

- `google-forms-survey-builder` — 利用例: `tech-talks`
- `slack-app-management` — Slack App を持つリポジトリのみ

## private（private-skills/・未追跡）

- `ca-pass`, `codex-private-smoke`

## repo-local で活用中

| ツール                                                                                    | 利用リポジトリ                      |
| ----------------------------------------------------------------------------------------- | ----------------------------------- |
| `agentation` / `agentation-self-driving` + `agentation-mcp`（MCP）                        | `caad-loca-bff`, `ultra-rss-reader` |
| `agent-browser`                                                                           | `caad-loca-bff`, `ultra-rss-reader` |
| `chrome-devtools`（MCP）                                                                  | `browser-toolkit`                   |
| `tauri-mcp-server`（MCP）                                                                 | `ultra-rss-reader`                  |
| `terraform-style-guide` / `terraform-test`（hashicorp）                                   | `ca-connect-site`, `caad-asta`      |
| `workers-best-practices` / `wrangler`（cloudflare）                                       | `keep-on`                           |
| `mcp-server-patterns`, `chatgpt-apps`                                                     | `caad-loca-bff`                     |
| `tauri`（EpicenterHQ）, `rust-best-practices`, `tauri-icon-gen`, `tauri-webview-geometry` | `ultra-rss-reader`                  |
| `marp-slide`, `slide-docs`                                                                | `tech-talks`                        |
| `manga-rss-bridge`                                                                        | `manga-rss-bridge`, `homelab-k3s`   |

## global MCP（root apm.yml の mcp:）

`context7`, `mcp-simple-voicevox`, `jina-reader`, `codex`, `1password`, `headroom`

## メンテナンス

- 更新タイミング: レーン間の移動、global への追加・撤去、repo-local の新規採用時
- repo-local の再スキャン: `ghq list -p` で各リポジトリの `apm.yml` を確認
