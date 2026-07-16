# Package Decisions

採用・撤去・見送りにした APM パッケージの意思決定ログ。1 パッケージ 1 セクション。
「なぜ入れたか / なぜ消したか / 再検討するなら何を見るか」を残す。

## emilkowalski/skills (emil-design-eng ほか)

- **Status: 採用・global（2026-07-16）**
- 正本: `emilkowalski/skills` リポジトリ配下
  - `skills/emil-design-eng`
  - `skills/review-animations`
  - `skills/improve-animations`
  - `skills/animation-vocabulary`
- 理由: UI Skills ディレクトリ精査で選定。Emil Kowalski のデザインエンジニアリング哲学
  （アニメーション判断フレームワーク、easing/duration 基準、Sonner 原則）に特化しており、
  `frontend-design`（生成方向）や `baseline-ui`（高速 deslop）と役割が重ならない。
  UI の仕上げ品質・モーション判断のレビュー基準として補完。同リポジトリの姉妹スキル
  （レビュー・監査プラン・用語逆引き）も併せて導入。
- 見送った同群: `vitest` / `pnpm`（モデル既知 + mise/lefthook 運用と衝突しうる）、
  `12-principles-of-animation`（`fixing-motion-performance` + `transitions-dev` でカバー）、
  `playwright-cli`（`browser-harness` で代替）、`shadcn`（`ui-styling` でカバー）。
- 再検討するなら: `frontend-design` / `baseline-ui` との発火競合が実運用で目立つ場合。

## make-interfaces-feel-better (jakubkrehel)

- **Status: 採用・global（2026-07-16）**
- 正本: `jakubkrehel/make-interfaces-feel-better/skills/make-interfaces-feel-better`
- 理由: UI Skills ディレクトリ精査で選定。マイクロインタラクション・タイポグラフィ・
  surface の具体的な数値基準（concentric border radius、scale(0.96)、tabular-nums、
  hit area 44px 等）を持ち、`baseline-ui` の高速パスに対する深掘りレビューとして棲み分け可能。
- 再検討するなら: `emil-design-eng` と指摘が重複しすぎる場合はどちらかに寄せる。

## 移管候補の提案（2026-07-15）

- **Status: 提案中**（2026-07-16 に `docs/skill-scope-proposals.md` を廃止し、
  未実施候補と判断基準・手順は [`docs/skill-inventory.md`](skill-inventory.md) の
  「移管候補（未実施）」へ集約）
- 最初の検討対象: `agentation` 系、`browser-harness` / `agent-browser`、React/UI 検証系
- 次の検討対象: UI デザインバンドルの必要サブセット、`understand` 系、社内 API 系
- 維持方針: APM 所有権、検証、安全性、横断的な環境運用スキルは global を維持
- 判断方法: 対象リポジトリで repo-local install と実作業を検証してから global 依存を外す

### agent-browser

- **Status: 保留撤去（2026-07-16）**
- 正本: `vercel-labs/agent-browser/skills/agent-browser`
- 理由: `browser-harness` を通常のブラウザ操作の標準にするため。Electron、Slack、Vercel
  Sandbox などの特殊用途が必要になった時だけ repo-local で再導入する。
- 再導入: 対象リポジトリで `apm install vercel-labs/agent-browser/skills/agent-browser`
  を実行する。

### ui-styling

- **Status: 保留撤去（2026-07-16）**
- 正本: `nextlevelbuilder/ui-ux-pro-max-skill` の upstream bundle
- 理由: `ui-ux-pro-max` と `baseline-ui` に UI/UX 判断と実装ガードレールがあり、
  shadcn/Radix 前提の総合ガイドを常時候補にする必要性が低いため。
- 再導入: 対象リポジトリで `apm install nextlevelbuilder/ui-ux-pro-max-skill --skill ui-styling`
  を実行する。

### google-forms-survey-builder

- **Status: 個別プロジェクト向けへ移管（2026-07-15）**
- 正本: `optional-skills/.apm/skills/google-forms-survey-builder/`
- 理由: Google Forms 案件に限定され、global rollout に含める必要がないため。
- 再導入: 利用リポジトリで `jey3dayo/apm-workspace/optional-skills#main` を追加し、
  `--skill google-forms-survey-builder` を選択する。

### slack-app-management

- **Status: 個別プロジェクト向けへ移管（2026-07-15）**
- 正本: `optional-skills/.apm/skills/slack-app-management/`
- 理由: Slack App を実装・運用するリポジトリに限定され、通常のリポジトリへ global
  rollout する必要がないため。
- 再導入: 利用リポジトリで `jey3dayo/apm-workspace/optional-skills#main` を追加し、
  `--skill slack-app-management` を選択する。

### banner-design

- **Status: global の skill subset から除外（2026-07-15）**
- 正本: `nextlevelbuilder/ui-ux-pro-max-skill` の upstream bundle
- 理由: embedded skill のため workspace から個別削除できないが、global manifest の
  `skills:` サブセットからは外せるため。
- 再導入: banner を使うリポジトリだけで upstream package を `--skill banner-design` 付きで導入する。

## ponytail (DietrichGebert/ponytail)

- **Status: 撤去（2026-07-07）**
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

- **Status: 撤去（2026-07-10）**
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

## skill-auditor / find-skills

- **Status: グローバル撤去・APM workspace-only 化（2026-07-13）**
- 経緯: もともと外部スキルとして global APM に登録していたが、skill-auditor は APM のスキル棚卸し用途、find-skills はスキル探索用途であり、通常の全リポジトリ作業に常時露出させる必要がないため撤去。
- 正本: `.apm/skills/skill-auditor/` と `.apm/skills/find-skills/`
- 配布面: `.claude/skills/<id>` と `.agents/skills/<id>` は正本のスキルディレクトリへの symlink。両方の skills ルートは実ディレクトリのままにする。
- 運用ルール: 正本だけを編集し、root `apm.yml` / `apm.lock.yaml` とグローバル `~/.claude/skills` / `~/.agents/skills` には戻さない。詳細な配置契約は `docs/apm-task-coverage.md` を参照。

## agent-curation

- **Status: グローバル撤去・APM workspace-only 化（2026-07-16）**
- 正本: `.apm/skills/agent-curation/`
- 理由: `catalog/agents/` と採用台帳を管理する、この APM workspace 自身の運用手順である。通常のリポジトリ作業で常時公開する必要はない。
- 配布面: `.claude/skills/agent-curation` と `.agents/skills/agent-curation` は正本のスキルディレクトリへの symlink。curated agent 自体は引き続き `catalog/agents/` から通常の catalog rollout で配布する。
- 運用ルール: スキル内容は正本だけを編集し、bridge は symlink の作成・付け替えのみ行う。root `apm.yml` / `apm.lock.yaml` と global catalog には戻さない。配置契約は `docs/apm-task-coverage.md`、curated agent の日常的な導線は `docs/agents-provenance.md` を参照。

## mermaid-diagrams

- **Status: 撤去（2026-07-13）**
- 理由: global skill context の常時候補から外し、現在の APM workspace の運用対象にも含めない判断。
- 再導入する場合: global APM に戻す前に、利用頻度と description budget への影響を確認する。

## デザイン / UI・UX / レビュー系スキルの棲み分け（2026-07-16）

- **Status: 整理実施（2026-07-16）**
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
