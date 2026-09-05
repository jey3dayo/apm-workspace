# 常駐プール経路

ユーザーが手で立てた pane の agent が `join` してチームに常駐し、同じ identity で複数タスクを受け続ける経路。`backlog-sweep` の Worker プールがこれにあたる。Lifecycle の 4・6・8 が使えないので、以下で置き換える。

**エージェントが pane を勝手に作らない。ユーザーが「用意して」と指示したときだけ作る。** その場合も `herdr workspace create` / `tab create` は使わない——command 指定フラグが無く bare shell しか起動しないのに、読み戻さなければ「起動した」と報告できてしまう。自分の pane からの `pane split --focus` → `pane run` → `pane process-info` での読み戻し、という `herdr` スキルの手順に従う（`backlog-sweep`「Worker プールを組む」に手順あり）。確認していない foreground process 名を報告に書かないこと。

| lifecycle   | spawn 経路                                              | 常駐プール経路                                                            |
| ----------- | ------------------------------------------------------- | ------------------------------------------------------------------------- |
| 3. 事前登録 | 同じ                                                    | 同じ。ただし固定名を再利用する                                            |
| 4. 起動     | `launch-worker.sh` で launchd 登録                      | ユーザーが pane を起動し、agent が `join` する。orchestrator は起動しない |
| 5. READY    | inbox の `READY(task_id)`                               | 同じ（inbox 一本化なのでそのまま使える）                                  |
| 6. 監視     | inbox + `worker.log` / `worker.exit` / launchd job 状態 | inbox のみ。下記の heartbeat 契約に置き換える                             |
| review role | spawn の profile / sandbox で read-only を実行時に強制  | 強制境界を確認できた pane のみ verdict 可。それ以外は advisory            |
| 8. 片付け   | `reset.sh` → `bootout` → 一時ディレクトリ削除           | `reset.sh` で identity を解放するだけ。pane は落とさない                  |

### 生存契約

`$run_dir/worker.log`・`worker.exit`・launchd job label が存在しないため、**crash・長時間コマンド・承認待ちを orchestrator 側だけでは区別できない**。この欠落を heartbeat とユーザーへの委譲で埋める。

- boot payload が無い経路なので、**最初のタスクメッセージが Worker プロトコルの唯一の注入口**になる。1通目に `WORKER.md` の解決済み絶対パス、`send-report.sh <team> <worker_name> <orchestrator>` の引数契約、下記の heartbeat 間隔を必ず含める
- worker は作業中、**5分を超えて無言にならないよう `WORKING` を送る**
- pane を `herdr` で立てた場合は、`herdr pane process-info` で `agent_status` と foreground process を読み戻してから生存判定する
- `WORKING` が10分途切れたら、orchestrator は推測で crash 判定せず、**該当 pane の状態確認をユーザーへ依頼する**（承認プロンプトで停止している可能性がある。pane は対話 TUI なので画面には出ているが、agmsg には何も流れない）
- 打ち切るときは `STOP(task_id)` を送る。応答が無い場合、spawn 経路のような job 停止手段は無いので、**ユーザーに pane で中断してもらう**

### 安全契約の置き換え

pane はユーザーが起動するので `run-claude-worker.sh` / `run-codex-worker.sh` を通らず、**macOS sandbox の書込境界も `-a never` も掛からない**。implement worker については次で担保する（reviewer は後述の「強制境界の有無で reviewer を 2 段に分ける」が正本）。

- pane の cwd を対象 worktree に固定する。`join.sh` / `identities.sh` は渡された project パスを記録・列挙するだけで **pane が実際にどこにいるかは検証しない**が、エージェントが `pane split --cwd` で立てた場合に限り `herdr pane process-info` で実 cwd を読み戻せる。ユーザーが手で立てた pane では機械的な確認手段が無く、cwd の正しさはユーザーが担保する
- 触るファイル集合が互いに素にできない行は直列化するか worktree を分ける
- したがって **orchestrator が `git diff` で実差分を読む（Lifecycle 7）ことが、機械的に成立する唯一の境界チェック**になる。省略しない。ただしこれは worker の成果物を受け入れるための確認であり、reviewer の read-only 違反を検出する手段としては不十分（後述）

**Reviewer の起動経路は spawn（`run-*-worker.sh review`）と pane 常駐の 2 つ。どちらも正規。** ただし verdict を出せるかは経路ではなく、**read-only の実行時強制が実際に掛かっているか**で決まる。

### 強制境界の有無で reviewer を 2 段に分ける

| 区分              | 条件                                               | 出せるもの                                         |
| ----------------- | -------------------------------------------------- | -------------------------------------------------- |
| verdict reviewer  | read-only の実行時強制が掛かっていることを確認済み | approval を gate する REVIEW（verdict + findings） |
| advisory reviewer | 強制が無い、または確認できない                     | 所見のみ。approve として受理しない                 |

強制境界を pane に掛ける手順は runtime で異なる。

- **Codex**: 対話起動でも `-p` / `-a` / `-s` を取れるため、scratch を cwd にして `cd "$(mktemp -d)" && codex -p agmsg-review -a never -m <model>` で立てれば spawn 経路と同じ境界になる。ただし `-p` は profile が `CODEX_HOME` 直下に無いと exit 0 で base config へ落ちる（fail-open）。`run-codex-worker.sh` が行っている「正本を `install -m 600` で置き直し `cmp` で一致検証」は手起動 pane では走らないので、**起動前に自分で `cmp` を通す**。通していない pane は advisory とする。
- **Claude**: `run-claude-worker.sh` の書込境界は `sandbox-exec` のラップで掛かっており、手で `claude` を起動した pane には掛からない。同等の境界を用意できない限り **advisory 固定**とする。

### status 比較は代替ではなく追加の検知

REVIEW 受信後の確認 (1) head SHA（+ diff ファイル方式なら checksum）が起動時と一致 (2) `git status --short` と `git ls-files --others --exclude-standard` が review 開始時点と差分なし、は行う。ただしこれは**実行時強制の代わりにならない**。次を検出できない。

- 編集して元に戻す、固定 SHA 以外の live tree を読んでから戻す
- `.git` 配下（`config`・hooks・refs・reflog・index・objects）への書込み
- gitignore 対象パスへの書込み
- 対象 project の外、および外部サービスへの書込み
- mtime だけの変更

**head SHA が一致していても fabricated approval は成立しうる。** したがって status 比較を根拠に advisory reviewer の所見を approve へ格上げしない。

### approval gate は作者と別 identity・別 session

approve を受理できる条件（作者と異なる identity かつ別 session / 別 context であること、対象の同一性と判断の独立性が別要件であること）は `orchestrator-worker` の「self-review 禁止（approval gate）」が正本。ここでは pane 常駐経路で追加になる部分だけを書く。

pane で verdict reviewer を立てる場合、**強制境界の確認結果を起動前に記録する**（profile の `cmp` 出力、scratch cwd、実際の起動引数）。記録が無ければ `review_mode: advisory` で起動する。この記録は SKILL.md の Lifecycle 7 が approve を受理する条件になっている。

報告形式は `review_mode` で分かれる。`verdict` は `verdict: approve | ready-with-fixes | reject`、`advisory` は `verdict` 行を持たず `assessment: clean | findings-present` を使う。**advisory に approve を作れる語彙を与えない**のがこの分割の要点で、契約は WORKER.md が正本。SHA 再確認の自己検証は両方に共通で効く。
