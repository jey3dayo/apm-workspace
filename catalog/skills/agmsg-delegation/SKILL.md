---
name: agmsg-delegation
description: >-
  agmsg + herdr で別プロセスの CC/Codex を worker / reviewer として起動し、
  タスク委譲またはレビュー外注を行う。orchestrator-worker の組み込み
  spawn_agent が使えない環境（Codex sol → luna 等)の手動経路。
disable-model-invocation: true
---

# agmsg-delegation

別プロセスの agent（herdr pane 上の Claude Code / Codex）へ、agmsg メッセージングで作業を委譲するライフサイクルを回す。組み込みサブエージェント（Agent tool / `spawn_agent`）が使える場合はそちらが正規経路であり、このスキルは **spawn 面の制約で組み込み経路が塞がっている場合の手動経路**である。

既知の制約（2026-08 時点）: `gpt-5.6-sol` は MultiAgent V2 のデフォルト `hide_spawn_agent_metadata = true` により `spawn_agent` から `model` 指定が事実上無効化されており、Terra/Luna への委譲ができない（`openai/codex` issue #31814, #34964 ほか）。このため Codex sol からの委譲は当面本スキルが実質的な標準経路になる。本スキルが起動する `codex --model gpt-5.6-luna` は新規プロセスの CLI 引数指定であり `spawn_agent` を経由しないため、このバグの影響を受けない。

tier 判定・委譲判定・タスク分割基準は `orchestrator-worker` スキルが正本。本スキルは transport と lifecycle だけを定義する。

## Role を決める

共通 lifecycle は同一で、role によって安全契約と報告フォーマットが異なる。

| role      | 自分の tier              | spawn する相手         | 相手の権限                   | 報告   |
| --------- | ------------------------ | ---------------------- | ---------------------------- | ------ |
| implement | Orchestrator (fable/sol) | worker (sonnet / luna) | 対象 worktree の編集可       | DONE   |
| review    | Worker (sonnet/luna)     | reviewer (fable / sol) | read-only。編集・commit 禁止 | REVIEW |

review role の fable/sol 指定は本スキル内の一時的な model override であり、`orchestrator-worker` の tier 対応表や既存 agent 定義（親モデル継承）を変更しない。Claude reviewer は fable が利用不可（未提供・rate limit・plan 制限など起動失敗）の場合のみ opus へフォールバックする。

## Guardrails

- worker と reviewer を同じ live working tree に同時接続しない。review は commit 済み SHA を対象にするか、review 中は implement worker への新規タスク送信を停止する
- review の入力は base/head SHA で固定する。固定 diff ファイル方式を採る場合は head SHA に加えファイルの checksum（`shasum -a 256`）も保持し、受信後に改変を検知する
- 並列 implement は触るファイル集合が互いに素であることが前提。互いに素にできなければ直列化するか worktree を分ける
- タスク文を shell command へ生 interpolation しない。boot payload は mode 600 の一時ファイル経由の quote-safe 方式にし、成功・timeout・crash の全経路で削除する
- review role の read-only は prompt 規約でなく実行時に強制する（下記の runtime 別起動コマンド）
- worker の commit / apply は自動化しない。orchestrator が実差分を自分の目で検証する

## Lifecycle

### 1. Preflight

- `herdr status` でサーバー稼働を確認
- worker runtime の CLI 存在を確認: `command -v codex` / `command -v claude`
- agmsg bootstrap 済みを確認（`~/.agents/skills/agmsg/` が存在）
- role/runtime 別の起動コマンドを確定する。review は書込権限を実行時に強制する:

| role      | Claude                                                 | Codex                                       |
| --------- | ------------------------------------------------------ | ------------------------------------------- |
| implement | `claude --model sonnet`                                | `codex --model gpt-5.6-luna`                |
| review    | `claude --model claude-fable-5 --permission-mode plan` | `codex --model gpt-5.6-sol -p agmsg-review` |

Claude review で fable の起動に失敗した場合は `claude --model opus --permission-mode plan` へフォールバックする（それ以外のフォールバックはしない。sonnet までは落とさず、opus も不可なら停止して報告する）。

Codex review に `--sandbox read-only` を使ってはならない。agmsg の送受信自体が DB 書込み（`send.sh` の messages.db 更新、`inbox.sh` の read_at 更新）と report 一時ファイル作成を必要とするため、完全 read-only では reviewer が READY/REVIEW/ACK を送信できない。代わりに、全ディスク read + agmsg 状態ディレクトリ（db/teams/run）と user temp のみ write を許可した profile `agmsg-review`（`CODEX_HOME/agmsg-review.config.toml`）を `-p` で layer する。対象 project は read のままにする。

profile の正本は本スキルの [agmsg-review.config.toml](agmsg-review.config.toml)（tracked asset）。**`-p` は profile ファイルが欠落していても exit 0 で base config にフォールバックする（fail-open）ため、起動前の検証が必須**:

```bash
diff ~/.agents/skills/agmsg-delegation/agmsg-review.config.toml ~/.codex/agmsg-review.config.toml
```

- 一致しない・存在しない場合は起動禁止。正本を `~/.codex/agmsg-review.config.toml` へコピーしてから再検証する
- 初回利用前の smoke: (1) 対象 project への write が拒否される (2) READY send 成功 (3) inbox で STOP 受信 (4) REVIEW/ACK send 成功 (5) temp cleanup 成功、の5点を実際に確認する。Claude review（plan mode）も agmsg の Bash 実行が無承認で通るか同じ smoke を行う

完了条件: herdr・CLI・role 別起動コマンド（review は profile の diff 一致確認込み）・agmsg の4点が確認済み。

### 2. 作業領域を固定する

- implement: 対象 worktree を決める。並列タスクはファイル集合が互いに素か確認する
- review: 対象を base/head SHA で固定する（未 commit の作業を見せる場合は先に commit するか、diff ファイル + checksum 方式にする）

完了条件: worker が触る（読む）領域が一意に特定され、tree 隔離規則に反していない。

### 3. Worker を事前登録する

`actas` と `send` は同一 team・同一 project の登録が前提。herdr 起動**前**に対象 project で登録する。worker_name は task-scoped の一意な名前（例: `<role>-<task_id>`）にし、既存名の再利用を避ける。

```bash
~/.agents/skills/agmsg/scripts/team.sh <team>   # 名前衝突を確認
~/.agents/skills/agmsg/scripts/join.sh <team> <worker_name> <claude-code|codex> <対象project絶対パス>
~/.agents/skills/agmsg/scripts/identities.sh <対象project絶対パス> <claude-code|codex>   # 登録を検証
```

完了条件: `identities.sh` の出力に、対象 project・runtime type・worker_name の組が exact に含まれる。

### 4. herdr pane で起動する

1. `herdr workspace list` / `herdr tab list` / `herdr pane list` で配置先を特定する
2. `herdr pane process-info --pane <pane_id>` で shell 待機中であることを確認する（agent や TUI 稼働中の pane は使わない）
3. `herdr pane split` を実行し、**戻り値から新 pane ID を取得**する
4. boot payload を mode 600 の一時ファイルに書く（`install -m 600 /dev/null <payloadファイル>` してから書き込む）。内容は task_id 付き初回プロンプト:
   - `/agmsg actas <worker_name>`（Claude）。Codex は actas を使わず、boot payload に「送信時は `send.sh <team> <worker_name> ...` を使う」と from 名を直接指示する
   - タスク本文（**タスクは必ず初回プロンプトに含める**。Codex の agmsg 既定 delivery は turn なので、起動後の agmsg 送信は次 turn まで届かない）
   - handshake 最小形: READY/DONE または REVIEW のフォーマット、task_id、timeout、WORKER.md の解決済み絶対パス
5. `herdr pane run <new_pane_id> "cd <対象project> && <role/runtime別起動コマンド> \"\$(cat <payloadファイル>)\""` で起動する
6. `herdr pane process-info` を再実行し、cwd と foreground process が期待通りか確認する

完了条件: 新 pane で worker CLI が起動し、process-info が一致している。

### 5. READY を待つ

readiness の source of truth は **inbox.sh で受信する READY(task_id) メッセージ**に一本化する（actas lock や pane 出力を readiness 判定に使わない）。

- `inbox.sh <team> <自分>` を timeout（既定 120 秒）付きでポーリングし、`READY <task_id>` を待つ
- Claude worker の READY 本文には `session: <session_id>` が含まれる契約。orchestrator はこれを lifecycle state に必ず保持し、終了時の `reset.sh` 第4引数に渡す。READY に session_id が無い場合は worker へ再送を求めるか、取得不能として crash cleanup 経路で処理する
- fallback として pane 出力監視を使う場合のみ: worker が agmsg send 成功後に terminal へ `READY <task_id>` マーカーを明示出力する契約とし、`herdr pane wait-output --match "READY <task_id>" --timeout 120000 <pane_id>` で待つ
- timeout 時は `herdr pane read` と `pane process-info` の出力を取得して原因を報告する

完了条件: READY(task_id) を受信した。timeout 時は診断情報を添えて停止・報告。

### 6. 報告を受けて検証する

**implement** — `DONE(task_id, status, files, tests, blockers)` 受信後:

- `git status --short` と `git diff` を自分の目で読む
- untracked は `git ls-files --others --exclude-standard` で列挙し、各ファイルの内容を `git diff --no-index /dev/null <file>` または直接 Read で検証する
- タスク定義に無い変更が入っていないか、test / typecheck が通るか確認する

**review** — `REVIEW(task_id, verdict, findings[{severity, file, line, evidence, recommendation}], checks)` 受信後:

- head SHA（+ diff ファイル方式なら checksum）が起動時と一致することを確認してから findings を採用する
- implement 用の diff 検証手順は適用しない

完了条件: role 別の検証を根拠にユーザーへ報告できる状態。

### 7. 片付ける

順序を守る（`pane close` は worker を強制終了し得るため、必ず ACK 後）。終了契約は runtime で異なる。

- Claude worker: STOP は Monitor 経由で届く。`STOP(task_id)` を送信し ACK を待つ
- **Codex worker**: idle セッションへの送信は届かない。WORKER.md の契約により、Codex worker は DONE/REVIEW 送信後も**同一 turn 内で** `inbox.sh` を timeout 付きポーリングして STOP を受信し ACK する。orchestrator は DONE/REVIEW 受信後すみやかに STOP を送る（worker のポーリング timeout 内に届かせる）

1. worker へ `STOP(task_id)` を送信し、ACK を待つ（timeout 付き。超過したら crash 扱いで次へ）
2. `herdr pane close <pane_id>`
3. `~/.agents/skills/agmsg/scripts/reset.sh <対象project絶対パス> <runtime_type> <worker_name> <session_id>`（orchestrator 自身の cwd ではなく **対象 project と worker_name を指定**する。Claude worker は READY で受け取った session_id を第4引数に渡して actas lock も解放する。session_id を取得できなかった場合のみ省略し、crash cleanup として記録する）
4. boot payload の一時ファイルを削除する

worker が crash / timeout した場合も同じ順序で、ACK 待ちを省略して 2→4 を実行し、pane read の最終出力を記録する。

完了条件: pane が閉じ、`identities.sh <対象project> <runtime_type>` の出力に worker_name が残っていない。

## Worker プロトコル

worker 側に注入する詳細プロトコル（報告フォーマット、途中相談ルール、role 別完了条件）は [WORKER.md](WORKER.md) が正本。boot プロンプトには handshake 最小形と WORKER.md の絶対パスだけを埋め込む。

WORKER.md は `~/.agents/skills/agmsg-delegation/WORKER.md` と `~/.claude/skills/agmsg-delegation/WORKER.md` の両方に配布されている必要がある。deploy 後に両方の存在と内容一致を確認する。
