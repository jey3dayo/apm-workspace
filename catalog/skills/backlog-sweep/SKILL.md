---
name: backlog-sweep
description: >-
  複数の面（todo.txt / plan リスト / issue / レビュー指摘）に散った backlog を1つの表に畳み、
  常駐 Worker プールへ長時間振り分けて消化する。
  「溜まってるタスクを消化して」「backlog を回して」のような、
  1タスクの依頼ではなく残作業全体を捌く依頼で使う。
---

# Backlog Sweep

1タスクの委譲は `orchestrator-worker` が扱う。本スキルは**残作業全体**を対象にし、散らばった台帳を1つの表へ畳んで、常駐 Worker プールへ長時間流し続ける運用を定義する。

tier 表・委譲判定・タスク分割基準・受領後の検証は `orchestrator-worker` が正本。本スキルが自前で持つのは**台帳統合・プール編成・振り分けループ・終了条件**の4点だけで、判定を二重に書かない。

## 1. 発火するか判定する

**未着手タスクが2面以上に散っているときだけ使う。** 面とは `todo.txt`、`plans/` などの plan ファイル群、GitHub issue、PR のレビュー指摘、CI の失敗一覧など、タスクが溜まる場所を指す。

1面しか無いなら畳む仕事が無いので、`orchestrator-worker` で普通に委譲する。タスク件数は判定に使わない（数えても閾値の根拠が無い）。

完了条件: 対象の面を列挙し、2面以上あることを示した。

## 2. 台帳を1つの表に畳む

各面を読み、未着手のものを1つの表へ集める。表の1行が Worker へ渡す1タスクになるので、**行の粒度は `orchestrator-worker` §3 の3点（触るファイル / 完了条件 / 検証コマンド）が書ける粒度**にする。書けない行は、書けるまで割るか、調査タスクとして分離する。

| 列           | 内容                                                       |
| ------------ | ---------------------------------------------------------- |
| ID           | 通し番号                                                   |
| 出典         | どの面から来たか（重複検出と、消化後の元の面の更新に使う） |
| 触るファイル | 他の行と互いに素か判定するための集合                       |
| 完了条件     | Worker がいつ止まるか                                      |
| 検証コマンド | その行だけで通せる test / typecheck / lint                 |
| 割当         | プールのどの member へ出したか                             |
| 状態         | 未着手 / 実行中 / 検証待ち / 完了                          |

触るファイルが重なる行は統合するか直列に並べる。並列で走らせるなら worktree を分ける。

表の永続化は任意。ただし**セッションが長く context 圧縮が見込まれるなら `tmp/backlog-sweep/<topic>.md` へ書き出す**。圧縮で振り分け履歴が消えると、同じ行を二重に投げるか取りこぼす。

完了条件: 全行に上表の列が埋まり、触るファイルの重なりが解消されている。

## 3. Worker プールを組む

**pane を勝手に作らない。ユーザーが「用意して」と言ったときだけ作る。** プールが必要そうなら、まず枚数・モデル・cwd を提示して指示を待つ。

ユーザーが立てるよう指示した場合は、`herdr` スキルの手順に従って作る。省略すると、起動の成否を読み戻さないまま「起動した」と報告する事故になる。

1. `herdr pane current` で自分の pane_id と workspace を確認する
2. `herdr pane split --pane <自分の pane_id> --focus --cwd <対象 worktree 絶対パス>` で分割する。**`workspace create` / `tab create` は使わない**（command 指定フラグが無く bare shell しか起動しないうえ、背面に作ると事故に気づけない）
3. `~/.agents/skills/agmsg/scripts/join.sh <team> <worker_name> <claude-code|codex> <対象project絶対パス>` で先に identity を登録する。runtime type はその member のモデルに合わせる（Codex 系なら `codex`、Claude 系なら `claude-code`）
4. `herdr pane run <新 pane_id> "cd <絶対パス> && <起動コマンド>"` で起動する。起動コマンドも member のモデルに合わせる（例: `codex -m gpt-5.6-luna`、`claude --model opus`）
5. `herdr pane process-info --pane <新 pane_id>` で foreground process と cwd を**読み戻す**。読み戻していないプロセス名を報告に書かない
6. 報告には pane_id + workspace label + 絶対 cwd + 実際に読み戻したプロセスを併記する

- tier は**編成時に固定**する。既定 Worker を N 枚 + 昇格先を 1 枚。到着した行を性質で振り分けるだけにし、実行中に tier を組み替えない。編成の例:
  - `luna`×N + `opus`×1 — Claude orchestrator から Codex Worker を使う混成プール。platform を跨ぐが、**どのモデルを立てるかを選ぶのはユーザー**なので `orchestrator-worker`「モデル名の指定は跨ぐ明示指示にあたる」に合致する
  - `sonnet`×N + `opus`×1 — Claude で完結
  - `luna`×N + `terra`×1 — Codex で完結
- 昇格先へ回すのは `orchestrator-worker` の昇格3条件（難しいデバッグ / セキュリティ境界 / 複数案のトレードオフ判断）に該当する行だけ。新しい条件を作らない
- member 名は固定名を**再利用**する。tier が混在するプールでは `luna-worker-1`..`luna-worker-3` / `opus-worker-1` のようにモデル名を含めると、割当表を見るだけで tier が読める。task-scoped な名前を毎回作らない。文脈を保った Worker はキャッシュが効くぶん安く、前提の再説明も要らない
- team は対象 repo 名と同一の永続 team。登録と検証の手順は `agmsg-delegation`「Worker を事前登録する」に従う

完了条件: 対象 project・runtime を引数にした `identities.sh` の出力に、全 member 名が含まれている（runtime が混在するプールは runtime ごとに実行して確認する）。

## 4. 振り分ける

- バリアを置かない。 全 member の完了を待たず、返った Worker から順に処理して次の行を送る。待つ間にリポジトリの状態が変わり、先行 Worker の前提が古くなる
- 1行返るたびに `orchestrator-worker` §5 の検証（`git diff` を自分の目で読む / タスク定義に無い変更が無いか / 検証コマンドが通るか）を実行してから、表の状態を更新する。**検証せずに次を送らない。** 壊れた前提の上に後半の行が積み上がる
- Worker の報告から派生タスクが出たら、その場で実装させず表へ新しい行として足す。プールへ流すのは表を経由した行だけにする
- 消化した行は、出典の面（`todo.txt` / plan ファイル / issue）へ結果を反映する

完了条件: 全行が完了か、明示的に見送りとして記録されている。

## 5. 終わる

表の全行が完了したとき、または人間が止めたときに終了する。

中断する場合は、表の現在状態を `tmp/backlog-sweep/<topic>.md` へ書き出してから止める。プールの片付けは `agmsg-delegation` の `references/resident-pool.md` に従い、`reset.sh` で identity を解放するだけにする。**人間が立てた pane は落とさない**。エージェントが作っていないものはエージェントが壊さない。

完了条件: 表の最終状態と、消化した行が出典の面へ反映済みであることを報告した。
