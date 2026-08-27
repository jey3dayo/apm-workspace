---
name: agmsg-delegation
description: >-
  agmsg で別プロセスの CC/Codex を worker / reviewer として起動し、
  タスク委譲またはレビュー外注を行う。orchestrator-worker の組み込み
  spawn_agent が使えない経路、別セッションへの引き継ぎ、または外部プロセスが必要な場合の経路。
  agent / セッション間の引き継ぎ（CC → Codex 等）メッセージの書式も定義する。
disable-model-invocation: true
---

# agmsg-delegation

別プロセスの agent（headless Claude Code / Codex）へ、agmsg メッセージングで作業を委譲するライフサイクルを回す。組み込みサブエージェント（Agent tool / `spawn_agent`）が使える場合はそちらが正規経路であり、このスキルは **native spawn が使えない場合、別セッションへ引き継ぐ場合、または外部プロセスが必要な場合の手動経路**である。**pane / workspace を勝手に作らない。ユーザーが指示したときだけ、読み戻し付きの手順で作る**（理由と常駐運用は「常駐プール経路」を参照）。

Codex CLI 0.147.0 以降は native `spawn_agent` から Luna を leaf worker として起動できるため、通常の Codex 内委譲では native spawn を優先する。本スキルが新規プロセスで起動する `codex -m gpt-5.6-luna exec` は、native spawn が利用できない環境、別セッション運用、または外部プロセスの分離が必要な場合の fallback とする。

tier 判定・委譲判定・タスク分割基準は `orchestrator-worker` スキルが正本。本スキルは transport と lifecycle だけを定義する。

## 引き継ぎ（handoff）メッセージ

**委譲**（新しいタスクを渡す）と**引き継ぎ**（進行中の作業を別 agent / セッションが継続する）は渡す中身が違う。引き継ぎは以下の書式に従い、transport は同じ agmsg を使う。lifecycle は不要で、本文を送るだけでよい。

- 他の artifact（spec、plan、ADR、issue、commit、diff）に既にある内容を本文へ複製せず、パスまたは URL で参照する
- 受け取り側が呼ぶべきスキルを **suggested skills** として列挙する
- API key、パスワード、個人情報は redact する
- 次セッションの目的が指定されていれば、それに合わせて内容を取捨する（全経緯の要約より、その目的に必要な決定事項を優先する）
- 保存が必要な場合は OS の一時ディレクトリへ置き、作業リポジトリへコミットしない

## Role を決める

共通 lifecycle は同一で、role によって安全契約と報告フォーマットが異なる。

| role      | 自分の tier                    | spawn する相手                 | 相手の権限                   | 報告   |
| --------- | ------------------------------ | ------------------------------ | ---------------------------- | ------ |
| implement | Orchestrator (fable/sol/terra) | worker (sonnet / luna)         | 対象 worktree の編集可       | DONE   |
| review    | Worker (sonnet/luna)           | reviewer (fable / sol / terra) | read-only。編集・commit 禁止 | REVIEW |

review role の reviewer モデル指定は本スキル内の一時的な model override であり、`orchestrator-worker` の tier 対応表や既存 agent 定義（親モデル継承）を変更しない。**review 外注の既定経路は Codex**: 起動時引数で `gpt-5.6-sol` / `gpt-5.6-terra` から選ぶ（既定は sol。設計影響が大きい・横断的なレビューは terra へ昇格し、必要なら `AGMSG_REVIEWER_EFFORT=high` などで effort も指定する）。Claude reviewer（fable 固定）は明示指定された場合のみ使う。orchestrator 側の Fable rate limit と枠を共有するため実行中 429 で run ごと失敗しうる。失敗した場合は同経路で再試行せず、Codex sol へ切り替えて再外注するか orchestrator が判断する（`--fallback-model opus` は起動失敗時のみ効き、実行中 429 は救えない）。

## Guardrails

- worker と reviewer を同じ live working tree に同時接続しない。review は commit 済み SHA を対象にするか、review 中は implement worker への新規タスク送信を停止する
- review の入力は base/head SHA で固定する。固定 diff ファイル方式を採る場合は head SHA に加えファイルの checksum（`shasum -a 256`）も保持し、受信後に改変を検知する
- 並列 implement は触るファイル集合が互いに素であることが前提。互いに素にできなければ直列化するか worktree を分ける
- タスク文を shell command へ生 interpolation しない。boot payload は mode 600 の一時ファイル経由の quote-safe 方式にし、成功・timeout・crash の全経路で削除する
- review role の read-only は prompt 規約でなく実行時に強制する（下記の runtime 別起動コマンド）
- Codex worker / reviewer は `run-codex-worker.sh` から `codex exec --ephemeral` で起動し、`-a never` を必須とする。承認が必要なコマンドは待機させず失敗として model へ返す。`--dangerously-bypass-approvals-and-sandbox` / `--yolo` は使わない
- Claude worker / reviewer は `run-claude-worker.sh` から `claude -p` で起動する。Claude の承認処理は無効化し、macOS sandbox で role 別の書込境界を強制する
- worker の commit / apply は自動化しない。orchestrator が実差分を自分の目で検証する

## Lifecycle

### 1. Preflight

- worker runtime の CLI 存在を確認: `command -v codex` / `command -v claude`。Claude は `command -v sandbox-exec` も必須
- agmsg bootstrap 済みを確認（`~/.agents/skills/agmsg/` が存在）
- role/runtime 別の起動コマンドを確定する。review は書込権限を実行時に強制する:

| role      | Claude                                                    | Codex                                                                                                          |
| --------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| implement | `run-claude-worker.sh implement <project> <payload-file>` | `run-codex-worker.sh implement <project> gpt-5.6-luna <payload-file>`                                          |
| review    | `run-claude-worker.sh review <project> <payload-file>`    | `run-codex-worker.sh review <project> <model> <payload-file>`（`gpt-5.6-sol` 既定 / `gpt-5.6-terra` へ昇格可） |

helper の解決先は `~/.agents/skills/agmsg-delegation/scripts/`。両 runtime とも headless mode と stdin prompt を使い、対話 TUI と shell interpolation を避ける。`launch-worker.sh` は専用の一時ディレクトリに launchd job label・ログ・exit status を残して detached に起動する。

Claude helper:

- role から model を固定する（implement は `sonnet`、review は `fable` + `--fallback-model opus`）。caller から model を渡さず、role と model の不整合を作らない
- 空の MCP 設定と `-p` を強制して workspace trust / MCP 確認を防ぎ、`--output-format stream-json --verbose` で無人実行中のイベントを worker log へ継続出力する
- `bypassPermissions` は macOS sandbox 内だけで使い、implement は対象 project 内だけ書込可、review は対象 project を read-only にする。`sandbox-exec` が無い環境では安全契約を弱めず停止する

Codex helper:

- `exec --ephemeral`、`-a never`、stdin prompt を強制し、review profile の内容一致を起動時に検証する
- implement role は `model_reasoning_effort` を既定 `xhigh` で付与する（`AGMSG_WORKER_EFFORT` で上書き可。昇格時は `max` を渡す）
- review role は既定では effort を付与せず Codex 既定に任せる。`AGMSG_REVIEWER_EFFORT` を指定した場合のみ `model_reasoning_effort` を付与する（例: terra レビューで `high`）

Codex review に `--sandbox read-only` を使ってはならない。agmsg の送受信自体が DB 書込み（`send.sh` の messages.db 更新、`inbox.sh` の read_at 更新）と report 一時ファイル作成を必要とするため、完全 read-only では reviewer が READY/REVIEW/ACK を送信できない。代わりに、agmsg 状態ディレクトリ（db/teams/run）だけを `writable_roots` に持つ profile `agmsg-review`（`CODEX_HOME/agmsg-review.config.toml`）を `-p` で layer する。**`writable_roots` は symlink 成分を含むと Codex が exec を拒否する**（"symlinked writable roots are not supported"）。`~/.agents/skills/agmsg/db`・`teams` は `~/.local/state/agmsg/` への symlink なので、profile には canonical path を列挙する（列挙内容は profile 正本のコメントを参照）。

**profile の `sandbox_mode = "workspace-write"` は cwd を必ず書込可能にする。** そのため `run-codex-worker.sh` は review role で **cwd を専用スクラッチ（`mktemp -d`）へ逃がし**、対象 project を cwd にしない。project へは read のみで到達でき、payload が絶対パスで指示する。スクラッチは git repo でないので `exec --skip-git-repo-check` を併せて渡す。`writable_roots` に対象 project を足してはならない。足すと read-only 契約が黙って壊れる。

profile の正本は本スキルの [agmsg-review.config.toml](agmsg-review.config.toml)（tracked asset）。**Codex の `-p` は profile ファイルが欠落していても exit 0 で base config にフォールバックする（fail-open）ため、`run-codex-worker.sh` が起動前に正本を `~/.codex/agmsg-review.config.toml` へ `install -m 600` で置き直し、その後 `cmp` で一致を検証する**。`CODEX_HOME` は APM の配布面ではないため（`targets:` は runtime 種別のリストで、skills / agents ディレクトリと `~/.codex/AGENTS.md` しか配布しない）、この置き直しが catalog 正本への追従経路になる。

- 手動コピーは不要。catalog 側の profile を更新したら `mise run deploy` するだけでよい
- source が欠落、コピー失敗、コピー後も不一致のいずれでも helper は起動を拒否する（fail-closed）
- 初回利用前の smoke: (1) review は対象 project への write が拒否される (2) implement は対象 project 内の edit が成功し project 外の write が拒否される (3) `send-report.sh` による READY send 成功 (4) DONE / REVIEW send 成功 (5) 全手順が承認画面・MCP 確認画面なしで完了、の5点を runtime ごとに実際に確認する

**`run-codex-worker.sh` は起動前に `writable_roots` の symlink 成分を検査して fail-closed する。** 不正な root が1つでもあると Codex は sandbox 構築自体に失敗し、**agmsg と無関係なコマンドまで起動前に全拒否する**。worker 側からは「シェルすら起動できない」形にしか見えず、原因が設定にあると分からないまま停止する（2026-08-27 に実際に発生）。検査対象は role で異なる。

- implement: profile を layer しないため `CODEX_HOME/config.toml` の base config を検査する
- review: profile の `writable_roots` は base config を**置換**する（実測済み）ため、配置後の profile だけを検査する

検査に引っかかった場合は該当 root・ファイル・canonical path へ直す指示を名指しで出して exit 1 する。

完了条件: CLI・role 別起動コマンド（review は profile の diff 一致確認込み）・agmsg・`launch-worker.sh` の4点が確認済み。

### 2. 作業領域を固定する

- implement: 対象 worktree を決める。並列タスクはファイル集合が互いに素か確認する
- review: 対象を base/head SHA で固定する（未 commit の作業を見せる場合は先に commit するか、diff ファイル + checksum 方式にする）

完了条件: worker が触る（読む）領域が一意に特定され、tree 隔離規則に反していない。

### 3. Worker を事前登録する

`actas` と `send` は同一 team・同一 project の登録が前提。worker 起動**前**に対象 project で登録する。

- team 名は対象 repo 名と同一の永続 team を使う（1 repo = 1 team）。日付・issue 番号・topic を team 名に含めない。task-scoped な team を乱立させると identities・履歴・掃除の全部が破綻する
- worker_name は task-scoped の一意な名前（例: `<role>-<task_id>`）にし、既存名の再利用を避ける。task の識別は team 名でなく worker_name と task_id が担う
- 例外は常駐プール経路で、`worker-1`..`worker-N` や `luna-worker-1` のような固定名を再利用する（命名は `backlog-sweep`「Worker プールを組む」に従う）。この場合 task の識別は task_id だけが担う

```bash
~/.agents/skills/agmsg/scripts/team.sh <team>   # 名前衝突を確認
~/.agents/skills/agmsg/scripts/join.sh <team> <worker_name> <claude-code|codex> <対象project絶対パス>
~/.agents/skills/agmsg/scripts/identities.sh <対象project絶対パス> <claude-code|codex>   # 登録を検証
```

完了条件: 対象 project・runtime type を引数にした `identities.sh` の出力に、worker_name が exact に含まれる（出力は `team<TAB>agent` の2列で、project・runtime は引数側で固定される）。

### 4. Detached worker を起動する

1. `run_dir=$(mktemp -d "${TMPDIR:-/tmp}/agmsg-delegation.XXXXXX")` を作り、`chmod 700 "$run_dir"` を実行する。payload・launchd job label・ログ・exit status はこのディレクトリだけに置く
2. boot payload を `$run_dir/payload.md` に mode 600 で書く（`install -m 600 /dev/null "$payload"`）。内容は task_id 付き初回プロンプト:
   - `/agmsg actas <worker_name>`（Claude）。Codex は actas を使わず、boot payload に「報告本文を標準入力へ渡し、`send-report.sh <team> <worker_name> <orchestrator>` を使う」と exact な引数契約を指示する
   - タスク本文、handshake、無人実行契約、WORKER.md の解決済み絶対パス
3. `launch-worker.sh` に helper の固定引数を配列として渡し、直接起動する。shell command 文字列を組み立てない。launchd 配下は PATH が最小構成なので、helper は必ず絶対パスで渡す:
   - Claude: `~/.agents/skills/agmsg-delegation/scripts/launch-worker.sh "$run_dir" -- ~/.agents/skills/agmsg-delegation/scripts/run-claude-worker.sh <role> <対象project> "$payload"`
   - Codex: `~/.agents/skills/agmsg-delegation/scripts/launch-worker.sh "$run_dir" -- ~/.agents/skills/agmsg-delegation/scripts/run-codex-worker.sh <role> <対象project> <model> "$payload"`
4. 出力された launchd job label と log path を保存し、`launchctl print "gui/$(id -u)/$(cat "$run_dir/worker.label")"` が成功することを確認する。起動失敗時は `$run_dir/worker.log` と `$run_dir/worker.exit` を読んで原因を記録する

完了条件: worker job が launchd に登録され、ログ出力先と task_id が対応付けられている。

### 5. READY を待つ

readiness の source of truth は **inbox.sh で受信する READY(task_id) メッセージ**に一本化する（actas lock や worker log を readiness 判定に使わない）。

- `inbox.sh <team> <自分>` を timeout（既定 120 秒）付きでポーリングし、`READY <task_id>` を待つ
- Claude worker の READY 本文には `session: <session_id>` が含まれる契約。orchestrator はこれを lifecycle state に必ず保持し、終了時の `reset.sh` 第4引数に渡す。READY に session_id が無い場合は worker へ再送を求めるか、取得不能として crash cleanup 経路で処理する
- fallback として `$run_dir/worker.log` の `READY <task_id>` を確認してよいが、readiness 判定は inbox の READY に限る
- timeout 時は `launchctl print "gui/$(id -u)/$(cat "$run_dir/worker.label")"`、`tail -n 200 "$run_dir/worker.log"`、`$run_dir/worker.exit`（あれば）を取得して原因を報告する

完了条件: READY(task_id) を受信した。timeout 時は診断情報を添えて停止・報告。

### 6. 完了まで監視する

READY 後も DONE / REVIEW だけを無期限に待たず、agmsg と detached process の両方を監視する。

- `inbox.sh <team> <自分>` を最大60秒間隔でポーリングし、`WORKING` / `BLOCKED` / `DONE` / `REVIEW` を受信する
- valid message が120秒無い場合は、launchd job 状態、`tail -n 200 "$run_dir/worker.log"`、`$run_dir/worker.exit`（あれば）を取得して、長時間コマンド・crash・承認待ちを区別する。長時間コマンドが動作中なら待機を継続し、診断時刻を更新する
- 承認画面を検出した場合は Enter を自動送信しない。Codex では `-a never` 契約違反として最終出力を記録し、crash cleanup へ進む。Claude では安全な代替を指示できる場合だけ指示し、解消しなければ同様に cleanup する
- boot payload の task timeout を超えたら最終ログ・launchd job 状態・exit status を保存し、crash cleanup へ進む
- 作業を途中で打ち切りたい場合は `STOP(task_id)` を送る。ただし worker が拾うのは best-effort（WORKING の区切りで inbox を確認した時のみ）なので、応答が無ければ task timeout / crash cleanup 経路で job を落とす

完了条件: DONE / REVIEW / BLOCKED を受信したか、timeout / crash の診断情報が揃っている。

### 7. 報告を受けて検証する

**implement** — `DONE(task_id, status, files, tests, blockers)` 受信後:

- `git status --short` と `git diff` を自分の目で読む
- untracked は `git ls-files --others --exclude-standard` で列挙し、各ファイルの内容を `git diff --no-index /dev/null <file>` または直接 Read で検証する
- タスク定義に無い変更が入っていないか、test / typecheck が通るか確認する

**review** — `REVIEW(task_id, verdict, findings[{severity, file, line, evidence, recommendation}], checks)` 受信後:

- head SHA（+ diff ファイル方式なら checksum）が起動時と一致することを確認してから findings を採用する
- implement 用の diff 検証手順は適用しない

完了条件: role 別の検証を根拠にユーザーへ報告できる状態。

### 8. 片付ける

**DONE / REVIEW の受信が終了シグナルであり、成功経路に STOP/ACK handshake は無い**（worker は DONE/REVIEW 送信後すみやかに終了する契約）。STOP は途中中断専用の合図で、orchestrator が作業を打ち切りたい時だけ送る。worker が STOP を拾えるのは WORKING 送信の区切りで inbox を確認した場合に限る best-effort であり、応答が無ければ task timeout を待って crash cleanup と同じ手順で片付ける。

1. launchd job が終了するまで最大10秒待つ。終了しない場合は最終ログを保存して crash 扱いとし、job を bootout しない
2. `~/.agents/skills/agmsg/scripts/reset.sh <対象project絶対パス> <runtime_type> <worker_name> <session_id>`（orchestrator 自身の cwd ではなく **対象 project と worker_name を指定**する。Claude worker は READY で受け取った session_id を第4引数に渡して actas lock も解放する。session_id を取得できなかった場合のみ省略し、crash cleanup として記録する）
3. worker job が終了済みであることを確認して `launchctl bootout "gui/$(id -u)" "$run_dir/worker.plist"` を実行してから、`rm -rf -- "$run_dir"` で専用一時ディレクトリだけを削除する（登録は `launchctl bootstrap` なので解除も `bootout` を使う。旧 API の `launchctl remove` は使わない）

worker が crash / timeout した場合も同じ 1→3 の順序で片付け、最終ログ・launchd job 状態・exit status を記録する。job が終了していない場合は一時ディレクトリを残し、ユーザーへ job label とログパスを報告する。

完了条件: worker job が終了・解除され、専用一時ディレクトリが削除され、`identities.sh <対象project> <runtime_type>` の出力に worker_name が残っていない。

## 常駐プール経路

ユーザーが手で立てた pane の agent が `join` してチームに常駐し、同じ identity で複数タスクを受け続ける経路。`backlog-sweep` の Worker プールがこれにあたる。Lifecycle の 4・6・8 が使えないので、以下で置き換える。

**エージェントが pane を勝手に作らない。ユーザーが「用意して」と指示したときだけ作る。** その場合も `herdr workspace create` / `tab create` は使わない——command 指定フラグが無く bare shell しか起動しないのに、読み戻さなければ「起動した」と報告できてしまう。自分の pane からの `pane split --focus` → `pane run` → `pane process-info` での読み戻し、という `herdr` スキルの手順に従う（`backlog-sweep`「Worker プールを組む」に手順あり）。確認していない foreground process 名を報告に書かないこと。

| lifecycle   | spawn 経路                                              | 常駐プール経路                                                            |
| ----------- | ------------------------------------------------------- | ------------------------------------------------------------------------- |
| 3. 事前登録 | 同じ                                                    | 同じ。ただし固定名を再利用する                                            |
| 4. 起動     | `launch-worker.sh` で launchd 登録                      | ユーザーが pane を起動し、agent が `join` する。orchestrator は起動しない |
| 5. READY    | inbox の `READY(task_id)`                               | 同じ（inbox 一本化なのでそのまま使える）                                  |
| 6. 監視     | inbox + `worker.log` / `worker.exit` / launchd job 状態 | inbox のみ。下記の heartbeat 契約に置き換える                             |
| 8. 片付け   | `reset.sh` → `bootout` → 一時ディレクトリ削除           | `reset.sh` で identity を解放するだけ。pane は落とさない                  |

### 生存契約

`$run_dir/worker.log`・`worker.exit`・launchd job label が存在しないため、**crash・長時間コマンド・承認待ちを orchestrator 側だけでは区別できない**。この欠落を heartbeat とユーザーへの委譲で埋める。

- boot payload が無い経路なので、**最初のタスクメッセージが Worker プロトコルの唯一の注入口**になる。1通目に `WORKER.md` の解決済み絶対パス、`send-report.sh <team> <worker_name> <orchestrator>` の引数契約、下記の heartbeat 間隔を必ず含める
- worker は作業中、**5分を超えて無言にならないよう `WORKING` を送る**
- `WORKING` が10分途切れたら、orchestrator は推測で crash 判定せず、**該当 pane の状態確認をユーザーへ依頼する**（承認プロンプトで停止している可能性がある。pane は対話 TUI なので画面には出ているが、agmsg には何も流れない）
- 打ち切るときは `STOP(task_id)` を送る。応答が無い場合、spawn 経路のような job 停止手段は無いので、**ユーザーに pane で中断してもらう**

### 安全契約の置き換え

pane はユーザーが起動するので `run-claude-worker.sh` / `run-codex-worker.sh` を通らず、**macOS sandbox の書込境界も `-a never` も掛からない**。実行時強制を失う分は次で担保する。

- pane の cwd を対象 worktree に固定する。`join.sh` / `identities.sh` は渡された project パスを記録・列挙するだけで **pane が実際にどこにいるかは検証しない**が、エージェントが `pane split --cwd` で立てた場合に限り `herdr pane process-info` で実 cwd を読み戻せる。ユーザーが手で立てた pane では機械的な確認手段が無く、cwd の正しさはユーザーが担保する
- 触るファイル集合が互いに素にできない行は直列化するか worktree を分ける
- したがって **orchestrator が `git diff` で実差分を読む（Lifecycle 7）ことが、機械的に成立する唯一の境界チェック**になる。省略しない

review role は常駐プールで運用しない。read-only の実行時強制が profile 起動に依存しており、pane では担保できない。レビュー外注は従来どおり spawn 経路を使う。

## Worker プロトコル

worker 側に注入する詳細プロトコル（報告フォーマット、途中相談ルール、role 別完了条件）は [WORKER.md](WORKER.md) が正本。boot プロンプトには handshake と無人実行契約の最小形、WORKER.md の絶対パスだけを埋め込む。

WORKER.md、`scripts/send-report.sh`、`scripts/launch-worker.sh`、`scripts/run-claude-worker.sh`、`scripts/run-codex-worker.sh` は `~/.agents/skills/agmsg-delegation/` と `~/.claude/skills/agmsg-delegation/` の両方に配布されている必要がある。deploy 後に両方の存在・実行権限・内容一致を確認する。
