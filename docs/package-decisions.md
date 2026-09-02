# Package Decisions

採用・撤去・見送りにした APM パッケージの意思決定ログ。1 パッケージ 1 セクション。
「なぜ入れたか / なぜ消したか / 再検討するなら何を見るか」を残す。

## 1Password MCP

- Status: global APM から撤去・host-local user scope へ移管（2026-07-22）
- 理由: 1Password デスクトップアプリとローカル承認 UI に依存し、macOS、native Linux、
  WSL で実行コマンドが異なる。共有 `apm.yml` の macOS 絶対パスを WSL に配布すると
  MCP startup error になるため、ポータブルな global MCP と分離する。
- 現在の配置: `mise bootstrap` の final hook がホスト上の MCP コマンドを解決し、Codex / Claude
  の user-scope MCP を冪等に同期する。native 環境では `onepassword-mcp` / `1password-mcp`、
  WSL では Windows App Execution Alias の `1password-mcp.exe` を利用する。APM は同名エントリを
  所有せず、`~/.codex/config.toml` と `~/.claude.json` は生成先として扱う。
- 再検討するなら: APM が MCP エントリ単位の OS / capability 条件を正式サポートした時点で、
  host-local 配置からの再統合を検討する。

## Cursor user-scope MCP (`~/.cursor/mcp.json`)

- Status: 手書き維持（2026-07-25）
- 理由: APM の `apm install -g` は Cursor を user-scope 対象外にする（project の
  `.cursor/mcp.json` のみ）。更新頻度も低いため、同期スクリプトや host-local レーンは作らない。
- 現在の配置: `~/.cursor/mcp.json` を手編集。`apm.yml` の `mcp:` と内容が重なっても APM は
  ここを再生成しない。
- 再検討するなら: APM が `~/.cursor/mcp.json` への user-scope 書き込みを正式サポートした時点。

## emilkowalski/skills (emil-design-eng ほか)

- Status: 採用・global（2026-07-16）
- 正本: `emilkowalski/skills` リポジトリ配下
  - `skills/emil-design-eng`
  - `skills/review-animations`
  - `skills/improve-animations`
  - `skills/find-animation-opportunities`
  - `skills/apple-design`
- 理由: UI Skills ディレクトリ精査で選定。Emil Kowalski のデザインエンジニアリング哲学
  （アニメーション判断フレームワーク、easing/duration 基準、Sonner 原則）に特化しており、
  `frontend-design`（生成方向）や `baseline-ui`（高速 deslop）と役割が重ならない。
  UI の仕上げ品質・モーション判断のレビュー基準として補完。同リポジトリの姉妹スキル
  （レビュー・監査プラン・用語逆引き・アニメーション機会発見）も併せて導入。
  `find-animation-opportunities` は read-only でアニメーション追加候補を提案するのみ、
  実装は行わない点に注意（`improve-animations` / `review-animations` と役割分担）。
- 撤去: `animation-vocabulary`（2026-08-09）。用語逆引きはモデルが素で答えられるため、
  trigger を持つスキルとして常駐させる価値がない。`/review` `/fix` `/find` 系のように
  「頼みたい作業の完成品プロンプト」になる verb スキルは残す。
- 見送った同群: `vitest` / `pnpm`（モデル既知 + mise/lefthook 運用と衝突しうる）、
  `12-principles-of-animation`（`fixing-motion-performance` + `transitions-dev` でカバー）、
  `playwright-cli`（`browser-harness` で代替）、`shadcn`（`ui-styling` でカバー）。
- 再検討するなら: `frontend-design` / `baseline-ui` との発火競合が実運用で目立つ場合。

## make-interfaces-feel-better (jakubkrehel)

- Status: 撤去（2026-07-23、下記「skill 監査に基づく撤去」参照）
- 旧 Status: 採用・global（2026-07-16）
- 正本: `jakubkrehel/make-interfaces-feel-better/skills/make-interfaces-feel-better`
- 理由: UI Skills ディレクトリ精査で選定。マイクロインタラクション・タイポグラフィ・
  surface の具体的な数値基準（concentric border radius、scale(0.96)、tabular-nums、
  hit area 44px 等）を持ち、`baseline-ui` の高速パスに対する深掘りレビューとして棲み分け可能。
- 再検討するなら: `emil-design-eng` と指摘が重複しすぎる場合はどちらかに寄せる。

## 移管候補の提案（2026-07-15）

- Status: 提案中（2026-07-16 に `docs/skill-scope-proposals.md` を廃止し、
  未実施候補と判断基準・手順は [`docs/skill-inventory.md`](skill-inventory.md) の
  「移管候補（未実施）」へ集約）
- 最初の検討対象: `agentation` 系、`browser-harness` / `agent-browser`、React/UI 検証系
- 次の検討対象: UI デザインバンドルの必要サブセット、`understand` 系、社内 API 系
- 維持方針: APM 所有権、検証、安全性、横断的な環境運用スキルは global を維持
- 判断方法: 対象リポジトリで repo-local install と実作業を検証してから global 依存を外す

### agent-browser

- Status: global 撤去実施（2026-07-16）。repo-local では利用継続
  （`caad-loca-bff`、`ultra-rss-reader`）。同日に `apm prune` で
  trailofbits 系 3 件の orphan cache も削除。
- 正本: `vercel-labs/agent-browser/skills/agent-browser`
- 理由: `browser-harness` を通常のブラウザ操作の標準にするため。Electron、Slack、Vercel
  Sandbox などの特殊用途が必要になった時だけ repo-local で再導入する。
- 再導入: 対象リポジトリで `apm install vercel-labs/agent-browser/skills/agent-browser`
  を実行する。

### ui-styling

- Status: 保留撤去（2026-07-16）
- 正本: `nextlevelbuilder/ui-ux-pro-max-skill` の upstream bundle
- 理由: `ui-ux-pro-max` と `baseline-ui` に UI/UX 判断と実装ガードレールがあり、
  shadcn/Radix 前提の総合ガイドを常時候補にする必要性が低いため。
- 再導入: 対象リポジトリで `apm install nextlevelbuilder/ui-ux-pro-max-skill --skill ui-styling`
  を実行する。

### ui-ux-pro-max（managed skill 化）

- Status: managed skill として維持
- 正本: `nextlevelbuilder/ui-ux-pro-max-skill/.claude/skills/ui-ux-pro-max`
- 理由: subdir install だと `scripts/` などの相対参照が壊れるため、
  通常の subdir ref ではなく managed skill 化で扱う。

### google-forms-survey-builder

- Status: 個別プロジェクト向けへ移管（2026-07-15）
- 正本: `optional-skills/google-forms-survey-builder/`
- 理由: Google Forms 案件に限定され、global rollout に含める必要がないため。
- 再導入: 利用リポジトリで
  `jey3dayo/apm-workspace/optional-skills/google-forms-survey-builder#main` を追加する。

### slack-app-management

- Status: 個別プロジェクト向けへ移管（2026-07-15）
- 正本: `optional-skills/slack-app-management/`
- 理由: Slack App を実装・運用するリポジトリに限定され、通常のリポジトリへ global
  rollout する必要がないため。
- 再導入: 利用リポジトリで
  `jey3dayo/apm-workspace/optional-skills/slack-app-management#main` を追加する。

### premortem

- Status: 個別プロジェクト向けへ移管（2026-07-21）
- 正本: `optional-skills/premortem/`
- 理由: 実装前の失敗条件分析を必要とするリポジトリで明示導入すればよく、通常の全リポジトリへ global rollout する必要がないため。
- 再導入: 利用リポジトリで
  `jey3dayo/apm-workspace/optional-skills/premortem#main` を追加する。

### predictive-analysis

- Status: global catalog 撤去を commit（2026-07-21、rollout 待ち）
- 旧正本: `catalog/skills/predictive-analysis/`
- 理由: 全リポジトリへ常時配布する対象から外す判断。後継配置や利用リポジトリは未確定のため、別レーンへ複製せず catalog source を削除する。push 後の catalog install で lock と global target から撤去する。
- 再検討するなら: 実利用するリポジトリを特定してから、optional または repo-local のどちらが適切かを決め、git history から復元する。

### ca-pass / mdb-api / notica-api / telma-api

- Status: global dependency から撤去・repo-local / on-demand 化（2026-07-21）
- 正本: `caad-develop/claude-code-marketplace` の各 `plugins/service-integrations/<id>`
- 理由: 社内 API、VPN、認証境界に依存するため、全リポジトリへの自動配布ではなく利用側の `apm.yml` に閉じ込める。workspace catalog へコピーせず upstream を直接参照する。
- 個別導入 ref:
  - `caad-develop/claude-code-marketplace/plugins/service-integrations/ca-pass`
  - `caad-develop/claude-code-marketplace/plugins/service-integrations/mdb-api`
  - `caad-develop/claude-code-marketplace/plugins/service-integrations/notica-api`
  - `caad-develop/claude-code-marketplace/plugins/service-integrations/telma-api`
- 補足: `private-skills` の `ca-pass` overlay は machine-local な別レーンとして維持する。
- 追記（2026-08-21）: `ca-pass` だけが root `apm.yml` に残留していた drift を /improve 監査（#5）で検出し、manifest から実撤去した。利用するリポジトリは repo-local `apm.yml` へ上記 ref を追加する（`apm-repo-manifest` 参照）。

### banner-design

- Status: global の skill subset から除外（2026-07-15）
- 正本: `nextlevelbuilder/ui-ux-pro-max-skill` の upstream bundle
- 理由: embedded skill のため workspace から個別削除できないが、global manifest の
  `skills:` サブセットからは外せるため。
- 再導入: banner を使うリポジトリだけで upstream package を `--skill banner-design` 付きで導入する。

## ponytail (DietrichGebert/ponytail)

- Status: 撤去（2026-07-07）
- 経緯: 2026-07-03 に managed lane から manual-skills lane へ移行 → 2026-07-07 に全面撤去。
  skills は `manual-skills/.apm/skills/` から削除、手動管理だった hooks は
  `~/.claude/settings.json` と `~/.claude/hooks/ponytail/` から削除、
  孤児化した `apm_modules/DietrichGebert/ponytail` checkout も削除。
- 撤去理由:
  - `ponytail:` self-tagging コメント規約が実運用で誤発火（実セッションで 3/3 が誤用 —
    「上限付きの近道」ではなく単なる設計理由の説明に使われた）。
    モデルに名前付きトリガーを与えると表層マッチで過剰適用する既知の傾向
    （over-refusal / moderation over-sensitivity 系の研究と同型）に合致。
  - 独自タグはチームメイトに読めない語彙でレビュー時のノイズになる。
  - 有用部分（YAGNI ladder）は短いプロンプトで再現可能。
    検証: https://blog.scottlogic.com/2026/06/16/ponytail-yagni-and-the-problem-with-prompt-benchmarks.html
  - 判断基準: 「悩むぐらいなら使わない」。
- 再検討するなら: コメントタグ指示を除いた trimmed persona にするか、
  設計の壁打ちには `/grilling`（mattpocock/skills）を使う。

### 副産物の教訓: APM は Claude Code hooks 付きパッケージを壊して deploy する

ponytail 固有ではない、hooks を持つ任意のパッケージに再発しうる問題（2026-07-03 時点）:

- APM の managed rollout は package の `copilot-hooks.json` 形式
  (`bash`/`powershell`/`timeoutSec`) を `SessionStart`/`UserPromptSubmit` に変換してしまい、
  package 自身の `claude-codex-hooks.json` (`matcher`+`hooks`+`command`/`timeout`) を使わない。
  結果、`/doctor` が invalid hook JSON を報告する。
- `apm.lock.yaml` の `deployed_files` は hook のエントリポイントだけ追跡し、
  エントリポイントが `require()` する兄弟モジュールを配布しないため、
  deploy 後に `MODULE_NOT_FOUND` でクラッシュする。
- 回避策: hooks を持つパッケージは manual lane 化し、hooks は upstream checkout から
  全ファイルを手動コピーして各 target の hook config を直接管理する。
  信頼する前に `update-config` skill の "Constructing a Hook" の pipe-test を通すこと。

## linear / sentry (openai/skills/skills/.curated/*)

- Status: 撤去（2026-07-10）
- 経緯: `/doctor` の未使用スキル棚卸しで両方とも使用実績ゼロと判明。同時に
  claude.ai 側の managed MCP コネクタで Linear（47 tools）と Sentry（9 tools）が
  接続済みであることを確認し、apm.yml の依存 2 行を削除して deploy。
  ローカルの `linear` MCP サーバー（`npx mcp-remote https://mcp.linear.app/sse`）も
  `~/.claude.json` user スコープから撤去済み。
- 撤去理由と一般則: **claude.ai 側で managed MCP コネクタとして提供される
  サービスは、APM 管理のスキル / ローカル MCP で二重管理しない**
  （claude.ai 側管理 MCP > apm 管理スキル）。認証・トークン更新・ツール定義の
  メンテナンスがコネクタ側に集約され、ローカルの残骸が SSoT ドリフトの温床になるため。
- 判断基準: 対象サービスのコネクタが接続済みで、スキルの中身がコネクタと
  役割被り（API アクセス手順・read-only 照会ラッパー等）なら撤去。
  役割が被らないスキル（例: slack-app-management は Slack アプリ管理で
  SlackDB コネクタとは別役割）は未使用かどうかだけで判断する。
- 再検討するなら: claude.ai コネクタが使えない環境（headless / cron /
  コネクタ未認証のマシン）での CLI 作業が常態化した場合のみ、
  repo-local への追加を検討する。
- Sentry は上記のまま撤去を維持する。Linear は下記のとおり復活した。

## linear MCP + linear-task-ops（復活）

- Status: global 復活（2026-07-27）
- 経緯: claude.ai / ChatGPT のコネクタだけでは実現できない Linear 操作があり、
  CLI 側（Claude Code / Codex）でも同じ tool 群が必要になった。さらに両アプリの
  コネクタは同一の MCP だと想定していたが実際には剥離があり、issue の作成・編集
  （書き込み系）の反映が信頼できないケースが出た。加えて
  `catalog/skills/linear-task-ops`（JEY 固有のプロジェクトルーティング・ラベル
  規約・取引ログ書式・GraphQL フォールバック）が `adc2578` の catalog 整理で
  誤って削除されていた。
- 構成: MCP は root `apm.yml` の `mcp:` に `linear`
  （`streamable-http` / `https://mcp.linear.app/mcp`）として登録。旧構成の
  `npx mcp-remote .../sse` は使わない。スキルは `catalog/skills/linear-task-ops`。
- 二重管理にならない理由: MCP は CRUD だけを担い、スキルは workspace 固有の
  ルーティング・書式・運用ルールと MCP に無い操作の GraphQL フォールバックを担う。
  コネクタとの役割被りが無い（「役割が被らないスキルは撤去対象にしない」に該当）。
- 一般則の更新: 「コネクタ提供サービスは二重管理しない」は、**コネクタが
  当該操作を全部カバーしている場合**に限る。CLI 側で必要かつコネクタで
  不足する操作があるなら global APM 管理でよい。

## skill-auditor / find-skills

- Status: グローバル撤去・APM workspace-only 化（2026-07-13）
- 経緯: もともと外部スキルとして global APM に登録していたが、skill-auditor は APM のスキル棚卸し用途、find-skills はスキル探索用途であり、通常の全リポジトリ作業に常時露出させる必要がないため撤去。
- 正本: `.apm/skills/skill-auditor/` と `.apm/skills/find-skills/`
- 配布面: `.claude/skills/<id>` と `.agents/skills/<id>` は正本のスキルディレクトリへの symlink。両方の skills ルートは実ディレクトリのままにする。
- 運用ルール: 正本だけを編集し、root `apm.yml` / `apm.lock.yaml` とグローバル `~/.claude/skills` / `~/.agents/skills` には戻さない。詳細な配置契約は `docs/apm-task-coverage.md` を参照。

## agent-curation

- Status: グローバル撤去・APM workspace-only 化（2026-07-16）
- 正本: `.apm/skills/agent-curation/`
- 理由: `catalog/agents/` と採用台帳を管理する、この APM workspace 自身の運用手順である。通常のリポジトリ作業で常時公開する必要はない。
- 配布面: `.claude/skills/agent-curation` と `.agents/skills/agent-curation` は正本のスキルディレクトリへの symlink。curated agent 自体は引き続き `catalog/agents/` から通常の catalog rollout で配布する。
- 運用ルール: スキル内容は正本だけを編集し、bridge は symlink の作成・付け替えのみ行う。root `apm.yml` / `apm.lock.yaml` と global catalog には戻さない。配置契約は `docs/apm-task-coverage.md`、curated agent の日常的な導線は `docs/agents-provenance.md` を参照。

## mermaid-diagrams

- Status: 撤去（2026-07-13）
- 理由: global skill context の常時候補から外し、現在の APM workspace の運用対象にも含めない判断。
- 再導入する場合: global APM に戻す前に、利用頻度と description budget への影響を確認する。

## デザイン / UI・UX / レビュー系スキルの棲み分け（2026-07-16）

- Status: 整理実施（2026-07-16）
- 経緯: `ui-ux-pro-max` の利用頻度低下をきっかけに全量棚卸し。調査の結論は
  「巨大データベース型 → 小さく意見の強い taste 型への重心移動はあるが、
  0→1 選定（ui-ux-pro-max）とポリッシュ（emilkowalski）は役割が違い併用が定番」。

### 変更内容

- `nextlevelbuilder/ui-ux-pro-max-skill` を `ui-ux-pro-max` のみに縮小。
  `brand` / `design` / `design-system` / `slides` / `ui-styling` を撤去
  （claudekit 系メガスキル。shadcn 知識・自作 design 系スキルと重複、計約 6MB）。
- `emilkowalski/skill`（旧・単数形）→ `emilkowalski/skills`（新・複数形、6 スキル構成）へ切替。
  導入は `emil-design-eng` + `review-animations` + `improve-animations` の 3 つ。

- `agentation` / `agentation-self-driving` を global から撤去（repo-local で利用継続:
  `caad-loca-bff`、`ultra-rss-reader`）。

現状の役割マップ、レビュー系の使い分け、repo-local 活用状況、保留 watchlist は
[`docs/skill-inventory.md`](skill-inventory.md) に集約した。

## skill 監査に基づく撤去（2026-07-23）

- Status: 撤去（2026-07-23）
- 経緯: skill-auditor のポートフォリオ監査
  （`~/.claude/skill-report/2026-07-23T11-14-21/`）で UI デザイン系 9 スキルの密集と
  重複クラスタが指摘された。監査の注意点として、自動ルーティング活性が全体の約 5% と
  低く「自動発火 0」は無価値の証拠にならないため、撤去判断は「他スキルとの重複」を
  主根拠とした。superpowers 系（obra）は全維持。
- 撤去した 4 スキル:
  - `make-interfaces-feel-better`（jakubkrehel）: emil-design-eng / baseline-ui と
    領域重複。2026-07-16 導入時の再検討条件「emil-design-eng と指摘が重複しすぎる場合」
    に該当と判断。
  - `web-design-guidelines`（vercel-labs）: 一般規範で ui-ux-pro-max /
    frontend-design / design-system-review と広く重複。
  - `grill-with-docs`（mattpocock）: `grilling` とほぼ同機能の重複ペア。grilling を残した。
  - `empirical-prompt-tuning`（mizchi）: operator が名指しで呼ぶときのみのメタスキルで
    起動実績なし。
- 撤去見送り: `transitions-dev` / `ui-ux-pro-max` は bloated 判定だが手動起動実績が
  あるため維持（description トリムを別途検討）。`perman-aws-vault` /
  `1password` / `dotenvx` はインフラ系のため維持。
- 検証継続中のレビュー・アニメーション系スキルの一覧と撤去判断基準は
  [`docs/skill-inventory.md`](skill-inventory.md) の
  「検証中のレビュー・アニメーション系スキル」表を正とする。
- 再導入する場合: 表の撤去基準を満たさなくなった実運用上の理由を本ファイルに追記してから戻す。

## superpowers / mattpocock 系の再編（2026-08-09）

- Status: `obra/superpowers` 全 11 スキルを撤去、`mattpocock/skills` を兄弟込みで揃える
- 撤去: `brainstorming` / `dispatching-parallel-agents` / `executing-plans` /
  `finishing-a-development-branch` / `subagent-driven-development` /
  `systematic-debugging` / `test-driven-development` / `using-git-worktrees` /
  `using-superpowers` / `verification-before-completion` / `writing-plans`、
  および `mattpocock/skills` の `resolving-merge-conflicts` と `handoff`
- 理由: superpowers は「手順を飛ばす・検証せず完了宣言する」世代のモデルへの矯正として
  設計されたもので、その思想は本体の既定挙動と組み込み subagent（Agent tool /
  `spawn_agent`）へ吸収された。`using-git-worktrees` は自前の `git-worktree` と、
  計画系は `prepare-goal` / `review-plan` / `review-fix-loop` と役割が重複していた
- `handoff` の 4 原則（artifact は参照渡し・suggested skills・secrets redact・
  次セッションの目的に合わせる）は `agmsg-delegation` の「引き継ぎ（handoff）メッセージ」
  セクションへ移植した。`baton` は 2026-09-02 に撤去し、handoff は同セクションを直接使う。
  外部 8 行スキルへの依存を解消した
- 追加: `codebase-design` / `domain-modeling` / `research` / `prototype` /
  `setup-matt-pocock-skills`。`wayfinder` と `improve-codebase-architecture` は
  これらを前提に相互参照する設計で、単体では参照先が空振りしていた
- `writing-great-skills` は上流で `writing-for-agents` にリネーム（スキル本文に加え
  AGENTS.md / CLAUDE.md の書き方も対象）。manifest を差し替えた
- 残した判断: `browser-harness`（pi / opencode 向けの最低保証ブラウザ能力）、
  `screenshot`（Win / Mac / Linux 対応。Mac 専用の `peekaboo` を撤去して一本化）、
  `thermo-nuclear-code-quality-review`（レビュー文化の共通言語）、
  `emil-design-eng`、React 系（`react-doctor` / `react-best-practices`）
- `docs/superpowers/**`（2026-04-21 の APM global distribution 設計・計画文書 2 本）は
  2026-08-10 に `tmp/superpowers/` へ移し、追跡対象から外した。superpowers 由来の
  ワークフロー生成物であり、スキル実行の出力は `tmp/` に集約してコミットしないという
  運用原則に合わせる。内容は git history に残るため、必要なら
  `git show 062960a:docs/superpowers/specs/2026-04-21-apm-global-distribution-design.md`
  のように取り出せる。

## review 系スキルの整理（2026-08-14）

- Status: `code-review` と `review-plan` を catalog から撤去、
  `docs-entrypoint-review` を `docs-review` にリネーム
- `code-review` 撤去理由: Claude Code 組み込みの `/code-review`（adversarial verify つき
  バグ検出）・`/security-review`・`/simplify` と直接競合。星評価つき品質アセスメントが
  必要な場合は `thermo-nuclear-code-quality-review` で代替する
- `review-plan` 撤去理由: 実行前ゲートとしての導線が `prepare-goal` / `grilling` /
  組み込み plan mode と重複し、起動実績が乏しかった
- 残した判断: `review-board`（レーン振り分けハブ）と `review-fix-loop`（backlog 管理つき
  反復ループ）は独自導線ありとして検証継続。`docs-review` / `quiet-command-auditor` は
  ドメイン特化で組み込みに代替なし。`design-system-review` は 2026-09-02 に撤去し
  （`review-board` lane 1 で代替）、`scheduled-audit-ops` は 2026-09-02 に
  `optional-skills` へ移動した
- 再導入する場合: 組み込みレビューで賄えない要件（プロジェクト設定統合、
  星評価レポート等）が実運用で必要になった理由を本ファイルに追記してから戻す

## `architecture-boundary-docs` の撤去（2026-09-02）

- 撤去理由: 生成先 `docs/architecture-boundaries.md` を持つリポジトリが `ghq list -p`
  全体で 0 件で、2026-05-23 の導入以降に産物が残っていない。層構造・依存方向の
  文書化は `codebase-design` / `docs-manager` で賄える。
- 再導入する場合: 境界ドキュメントを実際に必要とするリポジトリ名と、
  `codebase-design` で不足した観点を本ファイルに追記してから戻す

## `baton` の撤去（2026-09-02）

- 撤去理由: `agmsg-delegation` の「引き継ぎ（handoff）メッセージ」セクションが正本となり、薄いラッパースキルを別に持つ必要がなくなった。

## `mcp-tools` の撤去（2026-09-02）

- 撤去理由: 配置判断は `~/.claude/CLAUDE.md`「MCP 配置方針」/ `catalog/AGENTS.md` / `apm-usage` に既にあり重複している。references 3 本（計 2,100 行超）は汎用知識で stale しやすく、context7 / 公式 docs で代替できる。固有価値だった起動失敗の切り分け手順は `apm-usage` に吸収した。

## `polish` / `design-system-review` の撤去（2026-09-02）

- `polish`: 利用実績が 0 で、lint→fix→再実行のループは `CLAUDE.md` の DoD に手順として吸収済み。
- `design-system-review`: 汎用観点は `catalog/skills/review-board/references/review-lanes.md` の lane 1 "Design System Review" が持つ。`SKILL.md` は特定 repo のパス（`src/design-system/index.ts` 等）と画面名を決め打ちしていて他 repo では空振りするため、repo 固有値は当該 repo の steering へ置く。

## `apm-deploy-verify` を workspace-only lane へ移動（2026-09-02）

- 移動理由: 手順が `mise run format / check / deploy:fresh` と `~/.claude/skills` ↔ `~/.agents/skills` の diff で構成され、これらは `~/.apm/mise.toml` にしかない。他 repo へ global 配布しても実行不能である。AGENTS.md ownership 表の Workspace-only skills に該当する。

## `scheduled-audit-ops` を optional-skills へ移動（2026-09-02）

- 移動理由: `SKILL.md` が `docs/prompts/config.toml` を必須とし、該当 repo は `ca-connect-site` の 1 件のみである。global 配布しても他 repo では起動即失敗する。会社 repo に個人ツールを持ち込まず個人 workspace で版管理するため `optional-skills`（repo-scoped lane）に置き、消費側 repo は `apm.yml` に direct ref を追加する。

## Nix external skill sources (`agent-skills-sources.nix`)

- Status: 廃止（意図して空のまま維持）
- 理由: external skill の配布を APM（root `apm.yml` / `apm.lock.yaml`）へ一本化したため、
  `~/.config/nix/agent-skills-sources.nix` は intentionally empty。空であることは
  ミスではなく撤去の結果。
- 再検討するなら: Nix 側で skill 配布を復活させる場合のみ。通常は APM レーンを使う。
