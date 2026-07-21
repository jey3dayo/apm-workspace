# Skill Inventory

スキル・MCP の配置の現状と、移管候補・保留の一元管理（2026-07-21 時点）。
「どこに何があるか」「次にどう動かすか」はこのファイルに集約する。
個々の採用・撤去の理由と経緯は [`package-decisions.md`](package-decisions.md) を参照する。

## レーン一覧

| レーン                 | 正本                                 | 配布                                    | 用途                                           |
| ---------------------- | ------------------------------------ | --------------------------------------- | ---------------------------------------------- |
| global（外部）         | root `apm.yml` の `dependencies.apm` | 全リポジトリへ自動 rollout              | 横断的に使う外部スキル                         |
| global（自作 catalog） | `catalog/skills/**`                  | 全リポジトリへ自動 rollout              | 個人の横断ワークフロー                         |
| ~/.apm 専用            | `.apm/skills/**`                     | この workspace 内の symlink bridge のみ | APM workspace 自身の運用手順                   |
| optional               | `optional-skills/<id>/**`            | 利用リポジトリで個別 ref を直接 install | 選択リポジトリだけのワークフロー               |
| private                | `private-skills/.apm/skills/**`      | ローカル Codex sync のみ・未追跡        | マシンローカルの overlay                       |
| manual                 | `manual-skills/.apm/skills/**`       | 手動配置                                | 通常レーンで壊れる upstream の受け皿（現在空） |
| repo-local             | 各リポジトリの `apm.yml`             | そのリポジトリのみ                      | ランタイム・認証・ブラウザに結び付くもの       |

## global（外部スキル: root apm.yml）

- デザイン・UI/UX: `frontend-design`, `ui-ux-pro-max`, `baseline-ui`,
  `fixing-accessibility`, `fixing-metadata`, `fixing-motion-performance`,
  `make-interfaces-feel-better`, `transitions-dev`, `web-design-guidelines`
- モーション（emilkowalski/skills）: `emil-design-eng`, `review-animations`,
  `improve-animations`, `animation-vocabulary`
- レビュー・監査: `hunk-review`, `thermo-nuclear-code-quality-review`,
  `improve`（shadcn）, `react-doctor`
- React / Web 実装: `composition-patterns`, `react-best-practices`,
  `browser-harness`, `screenshot`
- ワークフロー（obra/superpowers）: brainstorming, executing-plans,
  systematic-debugging, TDD, worktrees, verification ほか計 11
- Codex 連携（openai）: `codex-cli-runtime`, `codex-result-handling`,
  `gpt-5-4-prompting`, `gh-address-comments`, `gh-fix-ci`
- 社内（caad-develop）: `perman-aws-vault`, `caad-skill-deployer`
- その他: `understand` / `understand-dashboard`, `humanizer-ja`,
  `web-research`, mattpocock 系 5, `empirical-prompt-tuning`

## global（自作 catalog: catalog/skills/）

31 スキル。主な系統:

- APM・環境運用: `apm-usage`, `apm-repo-bootstrap`, `mise`, `mcp-tools`,
  `headroom`, `dotenvx-env-ops`, `1password-item-ops`, `herdr`
- レビュー・品質: `code-review`, `review-board`, `review-fix-loop`,
  `review-plan`, `polish`, `quiet-command-auditor`
- デザイン: `design-md-workflow`, `design-system-review`
- リファクタリング・解析: `refactoring`, `similarity`
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
- `premortem` — 実装前の失敗条件分析が必要なリポジトリのみ

## private（private-skills/・未追跡）

- `ca-pass`, `codex-private-smoke`

## repo-local / on-demand へ移管済み

- `ca-pass`, `mdb-api`, `notica-api`, `telma-api` — global から撤去済み。
  必要な利用リポジトリの `apm.yml` から `caad-develop/claude-code-marketplace`
  の各 `plugins/service-integrations/<id>` ref を個別導入する。

## repo-local で活用中

global の一覧に無くても廃止ではない。各リポジトリの `apm.yml` が正本
（2026-07-16 時点の `ghq` 配下スキャン）。

| ツール                                                                                    | 利用リポジトリ                      | 用途                                                     |
| ----------------------------------------------------------------------------------------- | ----------------------------------- | -------------------------------------------------------- |
| `agentation` / `agentation-self-driving` + `agentation-mcp`（MCP）                        | `caad-loca-bff`, `ultra-rss-reader` | Agentation toolbar での UI アノテーション連携            |
| `agent-browser`（vercel-labs）                                                            | `caad-loca-bff`, `ultra-rss-reader` | ブラウザ自動化・Web UI 検証                              |
| `chrome-devtools`（MCP）                                                                  | `browser-toolkit`                   | Lighthouse・パフォーマンストレース等の DevTools 固有分析 |
| `tauri-mcp-server`（MCP）                                                                 | `ultra-rss-reader`                  | Tauri ランタイム検証                                     |
| `terraform-style-guide` / `terraform-test`（hashicorp）                                   | `ca-connect-site`, `caad-asta`      | Terraform 規約・テスト                                   |
| `workers-best-practices` / `wrangler`（cloudflare）                                       | `keep-on`                           | Cloudflare Workers                                       |
| `mcp-server-patterns`, `chatgpt-apps`                                                     | `caad-loca-bff`                     | MCP / ChatGPT Apps 実装                                  |
| `tauri`（EpicenterHQ）, `rust-best-practices`, `tauri-icon-gen`, `tauri-webview-geometry` | `ultra-rss-reader`                  | Tauri / Rust 実装                                        |
| `marp-slide`, `slide-docs`                                                                | `tech-talks`                        | スライド制作                                             |
| `manga-rss-bridge`                                                                        | `manga-rss-bridge`, `homelab-k3s`   | プロジェクト固有運用                                     |

## global MCP（root apm.yml の mcp:）

`context7`, `mcp-simple-voicevox`, `jina-reader`, `codex`, `headroom`

## デザイン / UI・UX / レビュー系の役割マップ

2026-07-16 の棚卸し結果（経緯は
[`package-decisions.md`](package-decisions.md) の「デザイン / UI・UX / レビュー系スキルの棲み分け」）。

| 役割                                       | スキル                                                                                                         |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| 0→1 デザイン選定（スタイル・色・フォント） | `ui-ux-pro-max`（本体のみ）                                                                                    |
| 美的方向性・脱テンプレ                     | `frontend-design`（anthropics）                                                                                |
| ベースライン修正（deslop）                 | `baseline-ui` / `fixing-accessibility` / `fixing-metadata`（ibelick）                                          |
| モーション taste・レビュー・監査           | `emil-design-eng` / `review-animations` / `improve-animations` / `animation-vocabulary`（emilkowalski/skills） |
| モーション実装スニペット                   | `transitions-dev`                                                                                              |
| UI ガイドライン準拠レビュー                | `web-design-guidelines`（vercel）                                                                              |
| デザインシステム準拠レビュー               | `design-system-review`（catalog 自作）                                                                         |
| UI レビューレーン選択ハブ                  | `review-board`（catalog 自作）                                                                                 |
| デザインドキュメント                       | `design-md-workflow`（catalog 自作）                                                                           |
| コードベース監査→計画（汎用）              | `improve`（shadcn）                                                                                            |
| React 診断                                 | `react-doctor`（millionco）                                                                                    |

### レビュー系の使い分け

- UI の見た目・ガイドライン準拠 → `web-design-guidelines`
- デザインシステム・トークン準拠 → `design-system-review`
- アニメーション・モーションの質 → `review-animations`（単発）/ `improve-animations`（全体監査→plan 生成）
- UI・フォーム・アクセシビリティ・マルチデバイスのレーン振り分け → `review-board`
- コード品質全般 → `code-review` / `hunk-review` / `thermo-nuclear-code-quality-review`
- 改善候補の洗い出し（実装しない）→ `improve`（shadcn、汎用）

## 保留・watchlist

- `apple-design`（emilkowalski）: Apple HIG 系。必要になったら global に 1 行追加。
- `fixing-motion-performance`（ibelick）/ `make-interfaces-feel-better`（jakubkrehel）:
  emil 新構成と発火競合したら間引く。モーション系は現在 emil 4 + ibelick 1 +
  transitions-dev + make-interfaces の系統があり、2〜3 週間の実運用で
  発火競合・指摘重複を確認する。

## 移管候補（未実施）

global から repo-local / optional へ移す候補。実施済みのもの
（`agentation` 系、`slack-app-management`、`google-forms-survey-builder`、
社内 API 系、UI バンドル縮小）は上の各レーンへ反映済み。

| 候補                                  | 推奨配置                                    | 判断理由                                                                                                                                         |
| ------------------------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `browser-harness`                     | 対象リポジトリの `apm.yml` または on-demand | ブラウザセッション・ログイン状態と結び付く。`agent-browser` は 2026-07-16 に global 撤去済み（repo-local: `caad-loca-bff` / `ultra-rss-reader`） |
| `understand` / `understand-dashboard` | 対象リポジトリの `apm.yml` または on-demand | 解析対象コードベースに結び付く                                                                                                                   |
| `perman-aws-vault`                    | 当面 global 維持                            | 複数 AWS リポジトリで同じ認証導線を使うため。移管するなら profile/credential 境界を明記後                                                        |

2026-07-16 の棚卸しで global 維持を決定したもの（候補から除外）:
`react-doctor`, `composition-patterns`, `react-best-practices`,
`baseline-ui` ほか ibelick 系, `web-design-guidelines`, `transitions-dev`,
`frontend-design`, `ui-ux-pro-max`, `design-md-workflow`, `design-system-review`。

### 移管の判断基準

- 特定のフレームワーク、ランタイム、サービス、UI ワークフローに強く依存する
- 使わないリポジトリでも毎回グローバル候補として読み込まれる
- 認証情報、ブラウザセッション、ローカルアプリなどの境界をプロジェクト側へ閉じ込めた方が安全
- 未発火データは補助根拠に留め、適用範囲と対象リポジトリの実態を優先する

### 移管手順

1. 対象リポジトリと実際の利用者を決める
2. repo-local `apm.yml` で対象スキルの個別 ref を install し、check / 実作業を検証する
   （workspace-owned は `catalog/skills/` → `optional-skills/<id>/` へ移してから
   `apm install jey3dayo/apm-workspace/optional-skills/<id>#main`）
3. global root manifest から外す
4. `mise run deploy` 後に `~/.agents/skills` と `~/.claude/skills` の残存を確認する
5. このファイルと `docs/package-decisions.md` を更新する

## メンテナンス

- 更新タイミング: レーン間の移動、global への追加・撤去、repo-local の新規採用時
- repo-local の再スキャン: `ghq list -p` で各リポジトリの `apm.yml` を確認
