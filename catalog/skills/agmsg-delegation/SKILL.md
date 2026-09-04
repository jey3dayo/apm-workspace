---
name: agmsg-delegation
description: >-
  agmsg で別プロセスの CC/Codex を worker / reviewer として起動し、
  タスク委譲またはレビュー外注を行う。orchestrator-worker の組み込み
  spawn_agent が使えない経路、別セッションへの引き継ぎ、または外部プロセスが必要な場合の経路。
  agent / セッション間の引き継ぎ（CC → Codex 等）メッセージの書式も定義する。
---

# agmsg-delegation

別プロセスの agent（headless Claude Code / Codex）へ、agmsg メッセージングで作業を委譲するライフサイクルを回す。組み込みサブエージェント（Agent tool / `spawn_agent`）が使える場合はそちらが正規経路であり、このスキルは **native spawn が使えない場合、別セッションへ引き継ぐ場合、または外部プロセスが必要な場合の手動経路**である。**pane / workspace を勝手に作らない。ユーザーが指示したときだけ、読み戻し付きの手順で作る**（理由と常駐運用は [references/resident-pool.md](references/resident-pool.md) を参照）。

tier 判定・委譲判定・タスク分割基準・Reviewer の model 選定は `orchestrator-worker` スキルが正本。本スキルは transport だけを定義する。

## この文はどこに書くか（transport 切り分け規則）

ある文が次のどれに答えているかで置き場を決める。

1. 相手は誰か（tier、model 選定、昇格、Reviewer の model）→ `orchestrator-worker`。
2. 相手に何をさせ、結果をどう検証するか（委譲判定、分割、git diff 検証、DoD）→ `orchestrator-worker`。報告書式だけ本スキルの [WORKER.md](WORKER.md)。
3. メッセージ/プロセスを届け、成立させ、片付けるか（identity 登録・解放、handshake、payload、起動・監視・timeout・cleanup、同一性確認）→ 本スキル。runtime 非依存は本文、runtime 依存（Codex profile、sandbox-exec、launchd、writable_roots）は `references/`。
4. どれにも当たらない（価格、version 履歴、経緯）→ 書かない。

Codex を起動する場合は [references/codex-sandbox.md](references/codex-sandbox.md) を先に読む。

## 引き継ぎ（handoff）メッセージ

**委譲**（新しいタスクを渡す）と**引き継ぎ**（進行中の作業を別 agent / セッションが継続する）は渡す中身が違う。引き継ぎは以下の書式に従い、transport は同じ agmsg を使う。lifecycle は不要で、本文を送るだけでよい。

- 他の artifact（spec、plan、ADR、issue、commit、diff）に既にある内容を本文へ複製せず、パスまたは URL で参照する
- 受け取り側が呼ぶべきスキルを **suggested skills** として列挙する
- API key、パスワード、個人情報は redact する
- 次セッションの目的が指定されていれば、それに合わせて内容を取捨する（全経緯の要約より、その目的に必要な決定事項を優先する）
- 保存が必要な場合は OS の一時ディレクトリへ置き、作業リポジトリへコミットしない

Steward から Architect への昇格 handoff もこの書式を使う。

### envelope（task / handoff メッセージの必須フィールド）

受け側が自分の役を本文から推測せずに済むよう、task と handoff の 1 通目は次を必ず持つ。欠けている場合、受け側は役を確定できないものとして扱う（判定規則は `orchestrator-worker`）。

| フィールド        | 意味                                                               |
| ----------------- | ------------------------------------------------------------------ |
| `source_role`     | 送り手の役（Steward / Architect / Reviewer / Worker）              |
| `target_role`     | 受け手に担わせる役。これがあれば受け側の判定はこれで確定する       |
| `task_id`         | 以後のすべての報告に載せる識別子                                   |
| `report_contract` | 受け側が返す契約。`DONE` / `REVIEW` / `HANDOFF` / `NOTIFY`         |
| `review_mode`     | review のときのみ必須。`verdict`（強制境界を確認済み）/ `advisory` |

契約は 2 種類に分かれる。

- 返信を伴うもの（`DONE` / `REVIEW` / `HANDOFF`）は、受け側が結果を返す。`HANDOFF` で受けた Architect は、作業を終えたら handoff 書式で送り手へ返す（`orchestrator-worker` の「最終報告は、依頼が来た経路へ返す」）。ack は不要だが**最終結果は返す**。
- 返信を伴わないもの（`NOTIFY`）は、一方通行。送り手は渡した時点で関与が終わり、受け側は ack も結果も返さない。送り手は返信を待たず `reset.sh` まで進める。スキル不具合のフィールド報告がこれにあたる（導線は `catalog/AGENTS.md`）。

**ack が不要なことと、最終結果が不要なことは別である。** `NOTIFY` 以外で「返信不要」と扱うと、Steward → Architect → Steward → 人間 の報告経路が切れる。

`target_role` と `report_contract` は**対応していなければならない**（Worker↔`DONE`、Reviewer↔`REVIEW`、Steward / Architect↔`HANDOFF` または `NOTIFY`）。対応表と不整合な組合せ、表に無い値、必須 field の欠落はいずれも、受け側が役を確定せず `BLOCKED` を返す契約である（判定は `orchestrator-worker` の自己判定規則が正本）。役だけ渡して報告契約を省くのも欠落にあたる。

本文の口調や「人間が話しかけてきたように見えるか」は役の根拠にしない。同じ文面が user メッセージとしても hook 経由でも届くため、受け側から区別できない。

## Role を決める

共通 lifecycle は同一で、role によって安全契約と報告フォーマットが異なる。

| role      | 起動する側                                                | spawn する相手                 | 相手の権限                   | 報告   |
| --------- | --------------------------------------------------------- | ------------------------------ | ---------------------------- | ------ |
| implement | Orchestrator 機能を担う側                                 | worker (sonnet / luna)         | 対象 worktree の編集可       | DONE   |
| review    | Orchestrator 機能を担う側。spawn 経路と pane 経路の両方可 | reviewer (fable / sol / terra) | read-only。編集・commit 禁止 | REVIEW |

review role の reviewer モデル指定は本スキル内の一時的な model override であり、`orchestrator-worker` の tier 対応表や既存 agent 定義（親モデル継承）を変更しない。model は helper の引数。選定は `orchestrator-worker` の「Reviewer の tier」が正本。

## Guardrails

- worker と reviewer を同じ live working tree に同時接続しない。review は commit 済み SHA を対象にするか、review 中は implement worker への新規タスク送信を停止する
- review の入力は base/head SHA で固定する。固定 diff ファイル方式を採る場合は head SHA に加えファイルの checksum（`shasum -a 256`）も保持し、受信後に改変を検知する
- 並列 implement は触るファイル集合が互いに素であることが前提。互いに素にできなければ直列化するか worktree を分ける
- タスク文を shell command へ生 interpolation しない。boot payload は mode 600 の一時ファイル経由の quote-safe 方式にし、成功・timeout・crash の全経路で削除する
- review role の read-only は prompt 規約でなく実行時に強制する（下記の runtime 別起動コマンド）
- Codex worker / reviewer は `run-codex-worker.sh` から `codex exec --ephemeral` で起動し、`-a never` を必須とする。承認が必要なコマンドは待機させず失敗として model へ返す。この spawn 経路では `--dangerously-bypass-approvals-and-sandbox` / `--yolo` を使わない（ユーザーが手で pane を起動する常駐プール経路の例外は「pane で Codex worker を起動するときのサンドボックス選択」を参照）
- Claude worker / reviewer は `run-claude-worker.sh` から `claude -p` で起動する。Claude の承認処理は無効化し、macOS sandbox で role 別の書込境界を強制する
- worker の commit / apply は自動化しない。orchestrator が実差分を自分の目で検証する

## Lifecycle

### 1. Preflight

- worker runtime の CLI 存在を確認: `command -v codex` / `command -v claude`。Claude は `command -v sandbox-exec` も必須
- agmsg bootstrap 済みを確認（`~/.agents/skills/agmsg/` が存在）
- role/runtime 別の起動コマンドを確定する。review は書込権限を実行時に強制する:

| role      | Claude                                                    | Codex                                                                                                                                                   |
| --------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| implement | `run-claude-worker.sh implement <project> <payload-file>` | `run-codex-worker.sh implement <project> gpt-5.6-luna <payload-file>`                                                                                   |
| review    | `run-claude-worker.sh review <project> <payload-file>`    | `run-codex-worker.sh review <project> <model> <payload-file>`（許可 model は `orchestrator-worker` の tier 表が正本。script が fail-closed で検証する） |

helper の解決先は `~/.agents/skills/agmsg-delegation/scripts/`。両 runtime とも headless mode と stdin prompt を使い、対話 TUI と shell interpolation を避ける。`launch-worker.sh` は専用の一時ディレクトリに launchd job label・ログ・exit status を残して detached に起動する。helper が role から model / effort を固定し、caller は model を渡さない（Codex は起動時の引数）。`run-codex-worker.sh` は role ごとの model allowlist を fail-closed で検証し、不一致は起動前に exit 2 で拒否する。上書き変数は各 script の Usage / コメントを参照（値は scripts が正本）。

Claude helper は空の MCP 設定と `-p` を強制して workspace trust / MCP 確認を防ぎ、`--output-format stream-json --verbose` で無人実行中のイベントを worker log へ継続出力する。`bypassPermissions` は macOS sandbox 内だけで使い、implement は対象 project 内だけ書込可、review は対象 project を read-only にする。`sandbox-exec` が無い環境では安全契約を弱めず停止する。

Codex helper は `exec --ephemeral`、`-a never`、stdin prompt を強制し、review profile の内容一致を起動時に検証する。**worker が継承する MCP は allowlist で絞る**（既定 `context7,jina-reader`、`AGMSG_WORKER_MCP_ALLOW` で置換）。認証情報・GUI 操作・通知・タスク管理の MCP を leaf worker へ渡すことは能力面の境界を広げるため、明示したものだけ通す。allowlist にするのは、`config.toml` へ新しい MCP を足したときに既定で流れ込まないようにするため。plugin 由来のサーバは `config.toml` に節が無く扱えないので、目的は最小化でありゼロ化ではない。review profile の fail-open 対策・cwd scratch・`writable_roots` の symlink fail-closed 検査・launchd の `MISE_ENV` 継承は [references/codex-sandbox.md](references/codex-sandbox.md) を参照。

完了条件: CLI・role 別起動コマンド（review は profile の diff 一致確認込み）・agmsg・`launch-worker.sh` の4点が確認済み。初回利用前の smoke 5点は [references/runtime-smoke.md](references/runtime-smoke.md) を参照。

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

**linked worktree では canonical な repo root を渡す。** `join.sh` は worktree path を repo root へ正規化して登録するが、`identities.sh` に worktree path を渡すと空を返し、上の完了条件が成立しない。`git -C <worktree> rev-parse --path-format=absolute --git-common-dir` の親、または `git -C <worktree> worktree list --porcelain` の先頭 entry から repo root を求めて渡す。`agmsg` は外部パッケージなので本スキルからは直せず、呼び出し側で揃える。

### 4. Detached worker を起動する

1. `run_dir=$(mktemp -d "${TMPDIR:-/tmp}/agmsg-delegation.XXXXXX")` を作り、`chmod 700 "$run_dir"` を実行する。payload・launchd job label・ログ・exit status はこのディレクトリだけに置く
2. boot payload を `$run_dir/payload.md` に mode 600 で書く（`install -m 600 /dev/null "$payload"`）。内容は task_id 付き初回プロンプト:
   - `/agmsg actas <worker_name>`（Claude）。Codex は actas を使わず、boot payload に「報告本文を標準入力へ渡し、`send-report.sh <team> <worker_name> <orchestrator>` を使う」と exact な引数契約を指示する
   - タスク本文、handshake、無人実行契約、WORKER.md の解決済み絶対パス
3. `launch-worker.sh` に helper の固定引数を配列として渡し、直接起動する。shell command 文字列を組み立てない。launchd 配下は PATH が最小構成なので、helper は必ず絶対パスで渡す:
   - Claude: `~/.agents/skills/agmsg-delegation/scripts/launch-worker.sh "$run_dir" -- ~/.agents/skills/agmsg-delegation/scripts/run-claude-worker.sh <role> <対象project> "$payload"`
   - Codex: `~/.agents/skills/agmsg-delegation/scripts/launch-worker.sh "$run_dir" -- ~/.agents/skills/agmsg-delegation/scripts/run-codex-worker.sh <role> <対象project> <model> "$payload"`
4. 出力された launchd job label と log path を保存し、`launchctl print "gui/$(id -u)/$(cat "$run_dir/worker.label")" | /usr/bin/grep -E '^[[:space:]]*(state|pid|last exit code|runs) = '` で状態だけを読む。**素の `launchctl print` は継承した環境変数を全部出力し、秘密値を tool output へ露出させる**（実運用で発生）。必ず絞って読む。**行頭に anchor する**のは、`SECRET => token state = hunter2` のように値が検索語を含む環境行が、非 anchored なパターンを通り抜けて再露出するためである（実測済み）。`rg` ではなく `/usr/bin/grep` を絶対パスで使うのは、この診断が repo 外の cwd でも走り、mise shim の `rg` が解決できない場合があるため。起動失敗時は `$run_dir/worker.log` と `$run_dir/worker.exit` を読んで原因を記録する

完了条件: worker job が launchd に登録され、ログ出力先と task_id が対応付けられている。

### 5. READY を待つ

readiness の source of truth は **agmsg DB に届いた READY(task_id) メッセージ**である（actas lock や worker log を readiness 判定に使わない）。`inbox.sh` はその取得手段の1つであり、session-start の watcher が常駐しうる環境では既読化の影響を受ける。

- `inbox.sh <team> <自分>` を timeout（既定 120 秒）付きでポーリングし、`READY <task_id>` を待つ
- `pgrep -f 'agmsg/scripts/watch.sh'` が watcher 常駐を示す場合は、`history.sh <team> <自分>` も併用して task_id の READY を DB から確認する
- Claude worker の READY 本文には `session: <session_id>` が含まれる契約。orchestrator はこれを lifecycle state に必ず保持し、終了時の `reset.sh` 第4引数に渡す。READY に session_id が無い場合は worker へ再送を求めるか、取得不能として crash cleanup 経路で処理する
- fallback として `$run_dir/worker.log` の `READY <task_id>` を確認してよいが、readiness 判定は agmsg DB の READY に基づく
- timeout 時は `launchctl print "gui/$(id -u)/$(cat "$run_dir/worker.label")" | /usr/bin/grep -E '^[[:space:]]*(state|pid|last exit code|runs) = '`、`tail -n 200 "$run_dir/worker.log"`、`$run_dir/worker.exit`（あれば）を取得して原因を報告する

完了条件: READY(task_id) を受信した。timeout 時は診断情報を添えて停止・報告。

### 6. 完了まで監視する

READY 後も DONE / REVIEW だけを無期限に待たず、agmsg DB に届いた DONE / REVIEW を正本として、agmsg と detached process の両方を監視する。

- `inbox.sh <team> <自分>` を最大60秒間隔でポーリングし、`WORKING` / `BLOCKED` / `DONE` / `REVIEW` を受信する
- `inbox.sh` に valid message が無く「無応答」と判定する前に、必ず `history.sh <team> <自分>` を task_id で確認する。watcher が常駐しうる（`pgrep -f 'agmsg/scripts/watch.sh'`）ため、既読化された DONE / REVIEW は history から復元する
- valid message が120秒無い場合は、launchd job 状態、`tail -n 200 "$run_dir/worker.log"`、`$run_dir/worker.exit`（あれば）を取得して、長時間コマンド・crash・承認待ちを区別する。長時間コマンドが動作中なら待機を継続し、診断時刻を更新する
- 承認画面を検出した場合は Enter を自動送信しない。Codex では `-a never` 契約違反として最終出力を記録し、crash cleanup へ進む。Claude では安全な代替を指示できる場合だけ指示し、解消しなければ同様に cleanup する
- boot payload の task timeout を超えたら最終ログ・launchd job 状態・exit status を保存し、crash cleanup へ進む
- 作業を途中で打ち切りたい場合は `STOP(task_id)` を送る。ただし worker が拾うのは best-effort（WORKING の区切りで inbox を確認した時のみ）なので、応答が無ければ task timeout / crash cleanup 経路で job を落とす

完了条件: DONE / REVIEW / BLOCKED を受信したか、timeout / crash の診断情報が揃っている。

### 7. 報告を受けて検証する

**implement** — `DONE(task_id, status, files, tests, blockers)` 受信後は、`orchestrator-worker` の「5. 受け取って検証する」の手順へ渡す。

**review** — `REVIEW(task_id, review_mode, verdict または assessment, findings, checks)` 受信後、次を**すべて**満たさない限り approve として受理しない。1 つでも欠ければ advisory として扱い、承認の根拠にしない。

1. head SHA（+ diff ファイル方式なら checksum）が起動時と一致する
2. 報告の `review_mode` が起動時に envelope へ書いた値と一致する（`advisory` を渡したのに `verdict` 行が返るのは契約違反）
3. `review_mode: verdict` の場合、**起動前に強制境界の証拠を記録している**。spawn 経路なら helper による profile 配置と `cmp` 成功、pane 経路なら [references/resident-pool.md](references/resident-pool.md) の確認手順の記録
4. reviewer の identity がレビュー対象の作者と異なる（approval gate は `orchestrator-worker` が正本）
5. pane 常駐経路では加えて、`git status --short` と `git ls-files --others --exclude-standard` が review 開始時点と差分なし

implement 用の diff 検証手順は適用しない。

完了条件: role 別の検証を根拠にユーザーへ報告できる状態。

### 8. 片付ける

**DONE / REVIEW の受信が終了シグナルであり、成功経路に STOP/ACK handshake は無い**（worker は DONE/REVIEW 送信後すみやかに終了する契約）。STOP は途中中断専用の合図で、orchestrator が作業を打ち切りたい時だけ送る。worker が STOP を拾えるのは WORKING 送信の区切りで inbox を確認した場合に限る best-effort であり、応答が無ければ task timeout を待って crash cleanup と同じ手順で片付ける。

1. launchd job が終了するまで最大10秒待つ。終了しない場合は最終ログを保存して crash 扱いとし、job を bootout しない
2. `~/.agents/skills/agmsg/scripts/reset.sh <対象project絶対パス> <runtime_type> <worker_name> <session_id>`（orchestrator 自身の cwd ではなく **対象 project と worker_name を指定**する。Claude worker は READY で受け取った session_id を第4引数に渡して actas lock も解放する。session_id を取得できなかった場合のみ省略し、crash cleanup として記録する）
3. worker job が終了済みであることを確認して `launchctl bootout "gui/$(id -u)" "$run_dir/worker.plist"` を実行してから、`rm -rf -- "$run_dir"` で専用一時ディレクトリだけを削除する（登録は `launchctl bootstrap` なので解除も `bootout` を使う。旧 API の `launchctl remove` は使わない）

worker が crash / timeout した場合も同じ 1→3 の順序で片付け、最終ログ・launchd job 状態・exit status を記録する。job が終了していない場合は一時ディレクトリを残し、ユーザーへ job label とログパスを報告する。

完了条件: worker job が終了・解除され、専用一時ディレクトリが削除され、`identities.sh <対象project> <runtime_type>` の出力に worker_name が残っていない。

## 常駐プール経路

ユーザーが手で立てた pane の agent が `join` してチームに常駐し、同じ identity で複数タスクを受け続ける経路。`backlog-sweep` の Worker プールがこれにあたる。Lifecycle の置き換え表、heartbeat 契約、安全契約の置き換え、Reviewer の pane 常駐可否は [references/resident-pool.md](references/resident-pool.md) を参照。

## Worker プロトコル

worker 側に注入する詳細プロトコル（報告フォーマット、途中相談ルール、role 別完了条件）は [WORKER.md](WORKER.md) が正本。boot プロンプトには handshake と無人実行契約の最小形、WORKER.md の絶対パスだけを埋め込む。deploy 後に両配布先の存在・実行権限・内容一致を確認する（`apm-deploy-verify`）。
