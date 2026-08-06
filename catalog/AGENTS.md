# AI 開発協働ガイド

全リポジトリ共通の AI 協働ルール。プロジェクト固有のルールはこの文書に置かず、各リポジトリの AGENTS.md / steering に置く。

## Definition of Done (DoD)

- 作業中は変更範囲に応じた軽い確認（touched file の format、関連テスト）に留め、push / PR / deploy など外部共有の直前に full gate（repo 定義の `check` / `test` / `ci` / `verify`）を実行する
- 共通基盤・依存・設定・生成物・永続データ構造の変更後は、早めに full gate へ昇格する
- lefthook が設定されているリポジトリでは pre-commit / pre-push フックを full gate とみなす。pre-push フックは `git push` 時に走るため、push 前に確認したい場合は `lefthook run pre-push` を手動実行する
- full gate を実行しない場合は、報告時に実行した軽い確認と省略理由を短く明示する

## 停止・確認ポリシー

ユーザーが「実装して」「直して」「進めて」など実作業を明示した場合は、追加承認を待たずに実装、品質確認、報告まで進める。承認確認や作業停止は以下のいずれかに該当する場合に限る。

- 破壊的操作、データ削除、履歴改変、外部公開、費用発生を伴う
- 選択によって UX や互換性が大きく変わる仕様判断、大規模な設計変更、依存追加、永続データ構造・セキュリティ境界の変更を伴う
- 既存のユーザー変更と衝突し、どちらを優先すべきか判断できない
- 必要な権限、認証、秘密情報、外部サービス状態が不足している
- 同一アプローチで **3回失敗** した（試行内容・各回の失敗理由・代替案を報告して停止する）

`main` / `master` ブランチ上では、`git restore`、`git checkout --`、`git reset --hard` など作業ツリーの変更を破棄・復元する操作を行わない。必要に見える場合でも、まず `git status --short` で対象を確認し、ユーザーに明示確認する。

## 開発原則

- linter の warning / error はコード側の inline disable コメントでなく、設定ファイル側のルール調整で対策する。正当な理由で恒常的に出るパターンはルールのオプションや scoped override で、意図をコメント付きで設定に記録する。inline disable は「その1箇所だけが真に例外」で設定に一般化すると他の違反を隠す場合に限る
- コードコメントは、コードだけでは読み取れない非自明な制約・判断理由・意図のみ書く。検討履歴や複数案の比較は PR・設計文書・ADR へ置く
- テストはユーザー価値・業務ルール・外部契約・不具合の再発防止に直結する振る舞いを優先し、実装詳細（内部呼び出し回数、要件に根拠のない数・順序・version の固定）への依存を避ける。数・順序・version 自体が明示された契約であるときは固定してよく、その根拠をテスト名またはコメントで示す

## モデル運用方針（Orchestrator-Worker）

高コストモデルを実装作業で使いすぎないよう、Orchestrator-Worker パターンで役割を分担する。Orchestrator は要件整理・設計・タスク分解・委譲先出力の検証を担い、実装は Worker へ渡す。

tier 対応表、委譲する / しないの判定、タスク分割基準、Claude / Codex での Worker 起動方法は `orchestrator-worker` スキルを正本とする。

### 推奨ワークフロー（経路の選択）

- 組み込みサブエージェント（Agent tool / `spawn_agent`）が使える場合はそれが正規経路
- Codex では `sol-advisor` plugin（`$sol-advisor:orchestration`）を推奨。標準レーンは Sol → Terra / High 実装 → 新規 Sol レビュー。コスパ優先時は依頼文に「Luna タスクレーンを使って」と明示すると Luna / Max の user-visible task へ委譲される（明示しない限り Terra。Luna が使えない場合は Terra へフォールバックせず停止する）
- Luna は高コスパ（同一トークン量でクレジット消費が Sol の約 1/25、Terra の約 1/10）だが、共有クレジットプールと利用上限を消費する。無料・無制限ではない
- Luna の直接起動は `codex -m gpt-5.6-luna`（`codex exec -m gpt-5.6-luna` も同様）
- spawn 面の制約で組み込み経路が塞がっている場合（Codex sol → luna 等）は `agmsg-delegation` スキルへ切り替える
- sol-advisor の導入・更新手順は `docs/package-decisions.md` を参照

### agent 定義側のモデル割り当て

- 各 agent のモデルは `catalog/agents/*.md` の frontmatter `model:` に書く。呼び出し時の指定漏れがあっても frontmatter の割り当てで動く
- Orchestrator 役はメインセッションが担い、agent 化しない
- レビュー・監査・本番運用判断系の agent（code-reviewer、deployment、terraform-operations など）は `model` を指定せず親モデルを継承させる

## コマンド選択

- 直接指定された URL の取得・DOM 抽出は `ax`（`--outline` / `--row` / `--md`）。mise 管理のため、初回利用前に `ax agent-context` で使い方を確認する
- Web 検索・検索結果経由の読み取りは `jina-reader`、JS 実行が必要なページはブラウザ操作ツール（選択は「MCP 配置方針」参照）
- ローカルリポジトリの場所特定は `ghq list -p`（名前で絞る場合は `ghq list -p <name>`）
- CLI が見つからない場合は PATH → リポジトリの `mise.toml` / `mise which` の順に確認し、未導入なら `mise install` を検討する。それでも使えない場合のみ理由を報告して fallback する

## ファイル操作原則

- ユーザー未確認の変更を `git restore` などで復元・破棄しない。特に `main` / `master` 上では restore 系操作を実行しない
- スキル実行や調査で作る一時的な出力（調査メモ、レビュー結果、レポート、スクリーンショット等）は、保存先の指定がない限りリポジトリ直下の `tmp/` 配下に集約し、原則コミットしない。スキルが `research_*` や `reports/` などの相対出力先を要求する場合も `tmp/<skill-or-topic>/` へ読み替える
- README.md や \*.md は明示的に要求された場合のみ作成する

## ドキュメント作成の優先順位

新しい知識を追加するとき:

1. Skill - 繰り返し使う知識
2. Agent - 自動実行すべきタスク
3. Command - ユーザーが手動実行する操作
4. Rules/Steering - プロジェクト固有のルール
5. llms.txt - agent 向けの短い入口・索引
6. Docs - 上記で表現できない場合のみ、最小限

## MCP 配置方針

global MCP はリポジトリをまたいで常時使う基盤だけに限定し、それ以外は repo-local または on-demand にする。

- global の実体は root `apm.yml` の `mcp:` を source of truth とし、固定リストをここに持たない（例: `mcp-simple-voicevox`（通知）、`context7`（current docs 確認）など）
- SaaS への接続は「アプリ側プラグイン / コネクタ（claude.ai・ChatGPT） > `apm.yml`（external skill / MCP） > catalog skill」の優先順で選び、上位が使えるなら下位で二重管理しない。アプリ側を優先するのは、認証・トークン更新・ツール定義のメンテナンスがアプリ側に集約されるため
- 片側のアプリにしかプラグイン / コネクタが無い場合は APM 管理にして両方へ配ってよい。両側に揃ったら撤去を検討する。接続状況の一覧は `~/.apm/docs/saas-connectors.md`、撤去判断の記録は `docs/package-decisions.md` を参照
- repo-local / on-demand: `tauri-mcp-server`（Tauri repo）、`peekaboo`（画面操作が必要なときだけ）
- ブラウザ操作:
  - 通常操作（クリック・フォーム入力・スクショ・コンソール確認）は `claude-in-chrome` または Codex Chrome アドオン
  - `chrome-devtools` は Lighthouse・パフォーマンストレース・ヒープスナップショットなど DevTools 固有分析が必要な repo だけに repo-local で追加
- 調査は source type で使い分ける: current docs は `context7`、直接指定された URL の取得・DOM 抽出は `ax`、Web 検索・検索結果経由の読み取りは `jina-reader`、広い比較調査は `web-research`、source-specific な到達性は専用 connector
- MCP 設定を永続変更する前に、次の ownership gate を完了する
  1. `~/.apm` が存在する場合は `apm-usage` を使う
  2. 対象 MCP を root `apm.yml`、この ownership map、配布スクリプトから検索する
  3. 編集対象を source of truth または deployed output に分類するまで書き込まない
  4. APM 管理なら source of truth を編集して再生成し、`~/.codex/config.toml` などの deployed output は直接編集しない
  5. 診断用の一時設定は `codex -c` などの one-shot override を使い、永続設定へ残さない
- `jina-reader` の transport、URL、認証、tool filter の正本は root `apm.yml`。変更後は `codex mcp list` と実際の検索を確認する
- repo-local MCP の固定リストは持たない。リポジトリ一覧は `ghq list -p`、実体は各リポジトリの `apm.yml` を確認する

## Git コミット規約

- 変更内容を簡潔に記述するのみ
- 追加の署名やフッターは不要

## Git Worktree 方針

- 実装開始時に隔離 workspace が必要かの判断は `superpowers-using-git-worktrees` スキル、操作仕様・`.worktrees/` 運用・作成削除手順は `git-worktree` スキルが正本
- worktree 操作は `git wt` を優先し、native `git worktree` は低レベルの cleanup・診断のみ
- コミット分割とメッセージ作成は `atomic-commit` スキルが担当し、worktree 操作の判断を持たせない

## コミュニケーション原則

- 最終回答は必ず日本語
- 番号だけの回答を求める場合は、同じメッセージ内に `1.` `2.` `3.` の各選択肢本文を必ず再掲する
- 確認や小さな判断は、`y/n`・番号・短い語句だけで返答できる聞き方にする

### 音声通知ルール

- 設定は `speaker=1` `speedScale=1.3` `async=true` を使う
- タスク完了時は必ず、重要なお知らせやエラー発生時にも `mcp-simple-voicevox` で音声通知を行う
- `mcp-simple-voicevox` tool が露出していないターンでは、音声通知を省略し、未実行だったことを報告しない
- 文面は 100 文字以内で結果のみ。技術的詳細は含めず、英単語はカタカナへ変換し、不要なスペースを削除する
- タイミングは命令受領時・作業開始時・作業中・進捗報告時・完了時を基本とする
- 例: 「了解です」「〜を開始します」「調査中です」「半分完了です」「完了です」

## 禁止事項

- 既存テスト・重要ファイルの無断削除
- any 型の導入
