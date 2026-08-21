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
  `transitions-dev`
- モーション（emilkowalski/skills）: `emil-design-eng`, `review-animations`,
  `improve-animations`, `find-animation-opportunities`, `apple-design`
- レビュー・監査: `hunk-review`, `thermo-nuclear-code-quality-review`,
  `improve`（shadcn）, `react-doctor`
- React / Web 実装: `react-best-practices`, `browser-harness`, `screenshot`
- GitHub 連携（openai）: `gh-address-comments`, `gh-fix-ci`
- 社内（caad-develop）: `perman-aws-vault`, `caad-skill-deployer`,
  `ai-banzuke`, `ai-butsukari-evidence-scout`
- 図生成: `diagram-design`（cathrynlavery, SHA pin）
- その他: `understand`, `humanizer-ja`, `agmsg`, `tuicr`,
  mattpocock 系（`grilling`, `writing-for-agents`, `wayfinder`,
  `improve-codebase-architecture`, `codebase-design`, `domain-modeling`,
  `research`, `prototype`, `setup-matt-pocock-skills`）

`MiniMax-AI/MiniMax-H3` 系 9 スキル（`h3-prompt-writing` と各種動画
ジェネレーター）は 2026-08-10 に撤去した。

`obra/superpowers` 全 11 スキルは 2026-08-09 に撤去した。判断理由は
[`docs/package-decisions.md`](package-decisions.md) の
「superpowers / mattpocock 系の再編」を参照。

## global（自作 catalog: catalog/skills/）

27 スキル。主な系統:

- APM・環境運用: `apm-usage`, `apm-repo-bootstrap`, `mise`, `mcp-tools`,
  `dotenvx-env-ops`, `1password-item-ops`, `herdr`
- レビュー・品質: `review-board`, `review-fix-loop`,
  `polish`, `quiet-command-auditor`
- デザイン: `design-md-workflow`, `design-system-review`
- リファクタリング・解析: `refactoring`, `similarity`
- ドキュメント: `docs-manager`, `docs-review`,
  `architecture-boundary-docs`, `japanese-tech-writing`
- Git・作業運用: `atomic-commit`, `git-worktree`, `ci-stability-hooks`,
  `prepare-goal`
- リサーチ: `web-research`（計画・並列委譲・Jina 収集・合成まで一体）

## ~/.apm 専用（.apm/skills/）

- `agent-curation` — catalog/agents と採用台帳の運用
- `skill-auditor` — スキル棚卸し
- `find-skills` — スキル探索

## optional（optional-skills/）

- `google-forms-survey-builder` — 利用例: `tech-talks`
- `slack-app-management` — Slack App を持つリポジトリのみ
- `premortem` — 実装前の失敗条件分析が必要なリポジトリのみ

## private（private-skills/・未追跡）

- `ca-pass`, `work-reports`, `work-log-maintenance`
  （社内情報を含むため private レーンへ移動。正本は github.com/jey3dayo/private-skills）

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

`context7`, `mcp-simple-voicevox`, `jina-reader`, `codex`

## デザイン / UI・UX / レビュー系の役割マップ

2026-07-16 の棚卸し結果（経緯は
[`package-decisions.md`](package-decisions.md) の「デザイン / UI・UX / レビュー系スキルの棲み分け」）。

| 役割                                       | スキル                                                                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| 0→1 デザイン選定（スタイル・色・フォント） | `ui-ux-pro-max`（本体のみ）                                                                                            |
| 美的方向性・脱テンプレ                     | `frontend-design`（anthropics）                                                                                        |
| ベースライン修正（deslop）                 | `baseline-ui` / `fixing-accessibility` / `fixing-metadata`（ibelick）                                                  |
| モーション taste・レビュー・監査           | `emil-design-eng` / `review-animations` / `improve-animations` / `find-animation-opportunities`（emilkowalski/skills） |
| モーション実装スニペット                   | `transitions-dev`                                                                                                      |
| デザインシステム準拠レビュー               | `design-system-review`（catalog 自作）                                                                                 |
| UI レビューレーン選択ハブ                  | `review-board`（catalog 自作）                                                                                         |
| デザインドキュメント                       | `design-md-workflow`（catalog 自作）                                                                                   |
| コードベース監査→計画（汎用）              | `improve`（shadcn）                                                                                                    |
| React 診断                                 | `react-doctor`（millionco）                                                                                            |

### レビュー系の使い分け

- UI の見た目・ガイドライン準拠 → `baseline-ui`（deslop）/ `design-system-review`
  （`web-design-guidelines` は 2026-07-23 撤去）
- デザインシステム・トークン準拠 → `design-system-review`
- アニメーション・モーションの質 → `review-animations`（単発）/ `improve-animations`（全体監査→plan 生成）
- UI・フォーム・アクセシビリティ・マルチデバイスのレーン振り分け → `review-board`
- コード品質全般 → 組み込み `/code-review` / `hunk-review` / `thermo-nuclear-code-quality-review`
- 改善候補の洗い出し（実装しない）→ `improve`（shadcn、汎用）

### 検証中のレビュー・アニメーション系スキル（2026-07-23 棚卸し）

レビュー系とアニメーション系は「どれを残すか検証するために意図的に複数入れている」領域。
skill 監査（`~/.claude/skill-report/2026-07-23T11-14-21/`）の結果を踏まえた現状と撤去判断基準。
自動発火はほぼ起きず明示 `/skill` 起動が中心のため、「発火 0」は撤去理由にしない。

| スキル                               | 系統      | 役割                                    | 起動実績（監査時点） | 撤去を判断する基準                                                     |
| ------------------------------------ | --------- | --------------------------------------- | -------------------- | ---------------------------------------------------------------------- |
| `emil-design-eng`                    | アニメ    | モーション taste・設計哲学              | 手動起動あり         | 維持前提。アニメ系の基準スキル                                         |
| `transitions-dev`                    | アニメ    | CSS トランジション実装スニペット        | 手動起動あり         | 維持。description が bloated 判定 → トリム対象                         |
| `review-animations`                  | アニメ    | 単発アニメーションレビュー              | なし                 | emil-design-eng で代替できると分かったら撤去                           |
| `improve-animations`                 | アニメ    | モーション全体監査 → plan 生成          | なし                 | `improve`（汎用）の nested subset と監査指摘。improve で足りるなら撤去 |
| `find-animation-opportunities`       | アニメ    | アニメ追加候補の発見（read-only）       | なし                 | 同上                                                                   |
| `fixing-motion-performance`          | アニメ    | モーション性能監査・修正                | なし                 | emil 系と指摘が重複したら間引く（従来 watchlist どおり）               |
| `apple-design`                       | アニメ/UI | Apple 流ジェスチャ・物理モーション      | 手動起動あり         | 維持                                                                   |
| `review-board`                       | レビュー  | UI レビューレーン選択ハブ               | なし                 | catalog 自作。レーン振り分けを使わないなら簡素化                       |
| `design-system-review`               | レビュー  | デザインシステム・トークン準拠          | なし                 | catalog 自作。維持                                                     |
| `hunk-review`                        | レビュー  | Hunk セッションでの対話的 diff レビュー | なし                 | Hunk 自体を常用しなくなったら撤去                                      |
| `thermo-nuclear-code-quality-review` | レビュー  | 保守性・構造の徹底監査                  | なし                 | 組み込み `/code-review` と指摘が重複しすぎたら撤去                     |
| `improve`                            | レビュー  | 監査 → 他 agent 向け実装 plan 生成      | なし                 | 維持。improve-animations の撤去判断の受け皿                            |
| `react-doctor`                       | レビュー  | React 診断                              | なし                 | `refactoring`（catalog）が参照するため維持                             |

2026-07-23 撤去済み: `make-interfaces-feel-better`, `web-design-guidelines`,
`grill-with-docs`, `empirical-prompt-tuning`（詳細は `package-decisions.md`）。

## 保留・watchlist

- `apple-design`（emilkowalski）: Apple HIG 系。必要になったら global に 1 行追加。
- `fixing-motion-performance`（ibelick）: emil 系と発火競合・指摘重複したら間引く。
  `make-interfaces-feel-better` は 2026-07-23 の skill 監査を受けて撤去済み。
  検証状況は上の「検証中のレビュー・アニメーション系スキル」表を正とする。

## 移管候補（未実施）

global から repo-local / optional へ移す候補。実施済みのもの
（`agentation` 系、`slack-app-management`、`google-forms-survey-builder`、
社内 API 系、UI バンドル縮小）は上の各レーンへ反映済み。

| 候補               | 推奨配置                                    | 判断理由                                                                                                                                         |
| ------------------ | ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `browser-harness`  | 対象リポジトリの `apm.yml` または on-demand | ブラウザセッション・ログイン状態と結び付く。`agent-browser` は 2026-07-16 に global 撤去済み（repo-local: `caad-loca-bff` / `ultra-rss-reader`） |
| `understand`       | 対象リポジトリの `apm.yml` または on-demand | 解析対象コードベースに結び付く。`understand-dashboard` は 2026-08-09 に撤去（従属品）                                                            |
| `perman-aws-vault` | 当面 global 維持                            | 複数 AWS リポジトリで同じ認証導線を使うため。移管するなら profile/credential 境界を明記後                                                        |

2026-07-16 の棚卸しで global 維持を決定したもの（候補から除外）:
`react-doctor`, `react-best-practices`,
`baseline-ui` ほか ibelick 系, `transitions-dev`,
`frontend-design`, `ui-ux-pro-max`, `design-md-workflow`, `design-system-review`
（`web-design-guidelines` と `composition-patterns` は撤去済み）。

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

## 社員向けスキル検索の設計メモ（2026-07-15、未実装）

global から専門スキルを外すために、軽量な「スキル検索・導入入口」だけを global に残す案を採用する。実装タスクは `todo.txt` の `+skill-search` を参照。

- 検索インデックスは `catalog/**`、`optional-skills/**`、root `apm.yml` / `apm.lock.yaml` の external 依存を統合する。
- 検索結果には skill id、用途、scope、source kind、upstream / package ref、trust・license 情報、導入コマンド、現在の global 配布状態を表示する。
- 導入先リポジトリで `apm.yml` を更新する。workspace-owned optional は単体 ref、external bundle は必要な場合だけ `--skill <id>` を使い、global へ直接追加しない。
- `find-skills` は検索体験・候補説明・導入導線の参考にする。ただし現状は skills.sh / `npx skills` 向けで、社内 catalog、optional skill collection、APM の scope 判定は扱わないため流用せず、APM-aware な index / CLI を別途設計する。

## メンテナンス

- 更新タイミング: レーン間の移動、global への追加・撤去、repo-local の新規採用時
- repo-local の再スキャン: `ghq list -p` で各リポジトリの `apm.yml` を確認
