# AI 開発協働ガイド

全リポジトリ共通の AI 協働ルール。プロジェクト固有のルールはこの文書に置かず、各リポジトリの AGENTS.md / steering に置く。

## 事実確認

- ファイル、フラグ、コマンド、機能が存在しないと断定する前に、その主張に最も近い一次情報を確認する。CLI は `--help`、機能は公式文書またはソース、導入済みパッケージはインストール先の実体を優先する
- 不存在や対応状況が回答の根拠になる場合は、確認に使ったコマンド、ファイル、文書を短く示す
- 最初の確認で判断できない場合は、別の一次情報を確認するか未確認であることを明示する。推測を事実として断定しない

## Definition of Done (DoD)

作業中は変更範囲に応じた軽い確認に留め、外部共有の直前に full gate を実行する。

### 検証粒度

| タイミング                                           | 実行する確認                                                |
| ---------------------------------------------------- | ----------------------------------------------------------- |
| 実装中・小さな修正後                                 | touched file の format、変更箇所の関連テスト                |
| 型・lint・テストに影響する変更後                     | 該当領域の focused check（typecheck / lint / unit test）    |
| 共通基盤・依存・設定・生成物・永続データ構造の変更後 | 早めに full gate へ昇格                                     |
| commit 前                                            | `git diff --check`、staged files の format / lint           |
| push / PR / deploy 前                                | full gate（repo 定義の `check` / `test` / `ci` / `verify`） |

- lefthook が設定されているリポジトリでは pre-commit / pre-push フックを full gate とみなす。pre-push フックは `git push` 時に走るため、push 前に確認したい場合は `lefthook run pre-push` を手動実行する
- full gate を実行しない場合は、報告時に実行した軽い確認と省略理由を短く明示する
- 非軽微な変更は外部共有前に、通常のコードレビュー観点での独立レビューを行う（指摘対応は最大3回。Codex native の別セッションレビューでもよい）

## 停止・確認ポリシー

ユーザーが「実装して」「直して」「進めて」など実作業を明示した場合は、追加承認を待たずに実装、品質確認、報告まで進める。承認確認や作業停止は以下のいずれかに該当する場合に限る。

- 破壊的操作、データ削除、履歴改変、外部公開、費用発生を伴う
- 選択によって UX や互換性が大きく変わる仕様判断、大規模な設計変更、依存追加、永続データ構造・セキュリティ境界の変更を伴う
- 既存のユーザー変更と衝突し、どちらを優先すべきか判断できない
- 必要な権限、認証、秘密情報、外部サービス状態が不足している
- 同一アプローチで **3回失敗** した（試行内容・各回の失敗理由・代替案を報告して停止する）

`main` / `master` ブランチ上では、`git restore`、`git checkout --`、`git reset --hard` など作業ツリーの変更を破棄・復元する操作を行わない。必要に見える場合でも、まず `git status --short` で対象を確認し、ユーザーに明示確認する。

## 秘密情報・環境変数の安全

- テストのために実在する API キーや秘密値を書き込み、上書き、再設定しない。専用の一時変数、ダミー値、または read-only の確認方法を使う
- `.env*` にある実在の秘密値を変更する場合は、値を出力せず対象キーと注入元を確認し、ユーザーの明示確認を得る
- 環境変数が戻った、反映されない、上書きされたと判断する前に、値を露出しない方法で解決後の環境と注入元を確認する。`mise` の `env_file` や `.env.local` による shadowing も確認対象に含める
- dotenvx 管理の詳細な診断・変更手順は `dotenvx` スキルを正本とする

## 開発原則

- エラーを握りつぶさない。境界で処理し、呼び出し元へ意味のある形で伝播する
- linter の warning / error はコード側の inline disable コメントでなく、設定ファイル側のルール調整で対策する。正当な理由で恒常的に出るパターンはルールのオプションや scoped override で、意図をコメント付きで設定に記録する。inline disable は「その1箇所だけが真に例外」で設定に一般化すると他の違反を隠す場合に限る
- コードコメントは、その package・関数の開発者・利用者に必要な Why（判断理由・制約）と What（契約・意図）を書く。コードをなぞるだけの How は書かない。検討履歴や複数案の比較は PR・設計文書・ADR へ置く
- `apm.yml` などの設定ファイルのコメントは、設定の契約、制約、恒常的に必要な判断理由に限る。一時的な状況説明、変更履歴、作業メモ、AI への指示などのメタコメントは差分や外部文書へ置く
- テストはユーザー価値・業務ルール・外部契約・不具合の再発防止に直結する振る舞いを優先し、実装詳細（内部呼び出し回数、要件に根拠のない数・順序・version の固定）への依存を避ける。数・順序・version 自体が明示された契約であるときは固定してよく、その根拠をテスト名またはコメントで示す

## モデル運用方針（Orchestrator-Worker）

高コストモデルを実装作業で使いすぎないよう、Orchestrator-Worker パターンで役割を分担する。Orchestrator は要件整理・設計・タスク分解・委譲先出力の検証を担い、実装は Worker へ渡す。

**実装 / 修正 / リファクタ / テスト追加 / 移行の依頼を受けたら、着手前に `orchestrator-worker` を読む。** 高級モデルが自分でコードを書き始めない。tier 対応表、委譲する / しないの判定、タスク分割基準、Claude / Codex での Worker 起動方法は同スキルを正本とし、ここには写さない（締め付けやモデル更改で頻繁に変わるため）。

**複数の面（`todo.txt` / plan リスト / issue / レビュー指摘）に散った backlog をまとめて捌く依頼は `backlog-sweep`。** 1タスクの委譲とは起点も終了条件も違うので、別スキルとして扱う。

### 推奨ワークフロー（経路の選択）

- 役割分担: `orchestrator-worker` は委譲判定・タスク分割の正本、Codex native の `spawn_agent` は標準 transport、`agmsg-delegation` は外部セッションや native spawn が使えない場合の fallback
- 組み込みサブエージェント（Agent tool / `spawn_agent`）が使える場合はそれが正規経路
- Worker のモデル名をユーザーが指定したら（例:「luna で」）、それが platform を跨ぐ明示指示にあたる。既定は同一 platform 内で完結させる
- pane / workspace を勝手に作らない。ユーザーが「用意して」と指示したときだけ、`herdr` スキルの `pane split --focus` → `pane run` → `pane process-info` で読み戻す手順で作る。読み戻していないプロセス名を報告に書かない
- spawn 面の制約で組み込み経路が塞がっている場合は `agmsg-delegation` スキルへ切り替える
- エージェント / セッション間の引き継ぎ（CC → Codex 等）は transport に `agmsg` を使い、本文は `agmsg-delegation` の引き継ぎメッセージ書式（artifact は参照渡し・suggested skills・secrets redact・次セッションの目的に合わせる）に従う
- Worker の `DONE` は未検証の申告として扱う。Orchestrator が実際の比較元を確定し、差分、変更対象、要求との対応を独立に確認する
- DoD に定める full gate は Orchestrator が実行し、Worker の実行報告では代替しない
- タスクで明示されていない依存 version、manifest、lockfile の変更は、要求上の必要性を確認できない限り採用しない

### スキルの不具合・摩擦を owner へ返す

スキルや agent を実運用で使って**不具合・契約の破れ・手順の摩擦**を踏んだら、その場の回避で終わらせずに `~/.apm` へ送る。回避策だけが各リポジトリに散ると、同じ穴を全員が踏み直す。

送るのは次のような内容。

- 手順どおりに実行して失敗した箇所（踏んだ経路とエラー実物）
- ドキュメントと実装が食い違っていた箇所
- 契約が成立しなかった箇所（完了条件が確認できない、報告書式が守られない等）
- 実測値（所要時間、消費、再試行回数）。判断の根拠になる
- 効いた点も書く。残す判断の材料になる

送りっぱなしでよい。**返信は来ないし、待たない。**

送信は team `apm`・宛先 `main-cc`。envelope は `source_role: Steward` / `target_role: Architect` / `task_id: <repo>-feedback-<topic>` / `report_contract: NOTIFY` の 4 field を必ず載せる（欠けると受け側は役を確定できず `BLOCKED` を返す契約）。`<name>` は task_id と同じ task-scoped な一意名にする。join / send / reset のコマンド列と envelope の書式定義は `agmsg-delegation` が正本。`HANDOFF` は最終結果を返す契約なので、一方通行の報告には使わない。

受け取り側（`~/.apm`）は**受け取るだけでよい**。ack を返す必要はなく、対応するかどうかと優先度は受け取り側が決める。

### agent 定義側のモデル割り当て

- 各 agent のモデルは `catalog/agents/*.md` の frontmatter `model:` に書く。呼び出し時の指定漏れがあっても frontmatter の割り当てで動く
- Orchestrator 役はメインセッションが担い、agent 化しない
- レビュー・監査・本番運用判断系の agent（code-reviewer、github-pr-reviewer、accessibility-auditor など）は `model` を指定せず親モデルを継承させる

## コマンド選択

| やりたいこと                        | 推奨                                                 | 回避                           |
| ----------------------------------- | ---------------------------------------------------- | ------------------------------ |
| 直接指定された URL の取得・DOM 抽出 | `ax`（`--outline` / `--row` / `--md`）               | `curl` + 使い捨て python/regex |
| JS 実行が必要なページ（SPA 等）     | ブラウザ操作ツール（「ブラウザ操作の選択」表を参照） | `ax` での無理な取得            |
| Web 検索・検索結果経由の読み取り    | `jina-reader`                                        | -                              |
| ローカルリポジトリの場所特定        | `ghq list -p`（絞り込みは `ghq list -p <name>`）     | `fd` / `find` での全域探索     |

- `ax` は mise 管理。初回利用前に必ず `ax agent-context` で使い方を確認する
- CLI が見つからない場合は PATH → リポジトリの `mise.toml` / `mise which` の順に確認し、未導入なら `mise install` を検討する。それでも使えない場合のみ理由を報告して fallback する

### ブラウザ操作の選択

コマンド仕様は各スキル / ツール側が正本。

| 目的                                                                                   | 推奨                                                      |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| ユーザーの画面を共有しながらの操作（クリック・フォーム入力・スクショ・コンソール確認） | `claude-in-chrome` または Codex Chrome アドオン           |
| 成果物やページをターミナルペインでユーザーの隣に出す・そのまま触ってもらう             | `terminal-browser`（kitty graphics 対応ターミナル必須）   |
| エージェント側で完結するヘッドレス自動化・スクレイピング・反復検証                     | `browser-harness`                                         |
| Lighthouse・パフォーマンストレース・ヒープスナップショットなど DevTools 固有分析       | `chrome-devtools`（必要な repo だけに repo-local で追加） |

## ファイル操作原則

- ユーザー未確認の変更を `git restore` などで復元・破棄しない。特に `main` / `master` 上では restore 系操作を実行しない
- スキル実行や調査で作る一時的な出力（調査メモ、レビュー結果、レポート、スクリーンショット等）は、保存先の指定がない限りリポジトリ直下の `tmp/` 配下に集約し、原則コミットしない。スキルが `research_*` や `reports/` などの相対出力先を要求する場合も `tmp/<skill-or-topic>/` へ読み替える
- 実装計画（plan）はスキルが `plans/` や `docs/**/plans/` を指定していても、リポジトリ直下の `plans/<skill-or-tool>/` へ読み替える（例: `plans/improve/`、`plans/superpowers/`）。次セッションでも読み返すため `tmp/` とは分け、原則コミットしない。Claude Code 本体が使う `.plans/` はそのまま扱う
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
- repo-local / on-demand: `tauri-mcp-server`（Tauri repo）など。デスクトップ / OS レベルのスクリーンショットは `screenshot` スキル（Win / Mac / Linux 対応）を使い、画面操作 MCP は必要になった repo だけに on-demand で入れる
- ブラウザ操作ツールの使い分けは「ブラウザ操作の選択」表を参照。MCP として repo-local 追加が必要なのは `chrome-devtools` のみ
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

- 操作仕様・`.worktrees/` 運用・作成削除手順は `git-worktree` スキルが正本
- worktree 操作は `git wt` を優先し、native `git worktree` は低レベルの cleanup・診断のみ
- コミット分割とメッセージ作成は `atomic-commit` スキルが担当し、worktree 操作の判断を持たせない

## コミュニケーション原則

- 最終回答は必ず日本語
- 3つ以上のツール、選択肢、コマンドを同じ評価軸で比較する場合は Markdown 表を優先する。単純な結論や手順に表を強制しない
- 番号だけの回答を求める場合は、同じメッセージ内に `1.` `2.` `3.` の各選択肢本文を必ず再掲する
- 確認や小さな判断は、`y/n`・番号・短い語句だけで返答できる聞き方にする

### 音声通知ルール

- 設定は `speaker=1` `speedScale=1.3` `async=true` を使う
- タスク完了時は必ず、重要なお知らせやエラー発生時にも `mcp-simple-voicevox` で音声通知を行う
- `mcp-simple-voicevox` tool が露出していないターンでは、音声通知を省略し、未実行だったことを報告しない
- 文面は 100 文字以内で結果のみ。技術的詳細は含めず、英単語はカタカナへ変換し、不要なスペースを削除する

## 禁止事項

- 既存テスト・重要ファイルの無断削除
- any 型・型アサーションの導入
