---
name: t3-steward
description: >-
  T3 Code の product 常駐 steward（`<product>: steward`）として動くとき、または steward の状況ファイル・
  台帳を読むときに使う。再開条件（心拍）、状況ファイルの項目と先書き、子スレッドの依頼文と追跡、
  マージ・stg 反映の権限、steward の引き継ぎ・交代を扱う。子スレッド側の決まり、worktree、
  ブラウザ、権限の共通基盤は t3-stack、判定・分割・tier は orchestrator-worker が持つ。
---

# T3 steward

product ごとに1本置く常駐メインセッションの運営手順。steward は台帳の持ち主、ゲートキーパー、子への分配者であり、重い作業は自分で抱えない。共通基盤（worktree、権限、スレッド名、引き継ぎ手段、ワーカーの報告契約、ブラウザ）は `t3-stack`、委譲判定・タスク分割・tier・verdict review は `orchestrator-worker`、複数の面に散った backlog の畳み方は `backlog-sweep` が持つ。ここにはそれらにない steward 固有の決まりだけを書く。公式の orchestration instructions と食い違う箇所は「公式より優先」と明記したものだけ、本スキルを優先する。

## 1. 起動時に確かめる

- Orchestrator 機能を担えるかは `orchestrator-worker` §1 の条件で判定する。Sonnet の steward は Opus advisor が使えることが前提で、起動時に確認する。使えなければ Opus の steward へ切り替えるか、Architect へ handoff する。ここでいう Architect への handoff は、設計判断用の Opus high の別スレッドへ渡すことと同じ意味。
- 状況ファイル（§2）を読み、冒頭の「現在の owner」が自分であることを確かめる。別の owner が書いてあれば、二重稼働になるので作業を始めない。
- 受け付けた依頼が §2 の台帳のどの行にも属さないなら、先に行を足してから子を起動する。

## 2. 状況ファイル（台帳）

状態の持ち主はスレッド履歴ではなく状況ファイル `~/tmp/iw/<product>-steward-status.md`。冒頭に次を置く。

- 現在の owner を1行（スレッドの threadId とリンク、交代日時）。外側の triage はこの threadId を保護リストと照合するので、リンクだけにしない。
- 「このファイルを読む者は `t3-steward` に従う」の1行。
- product の許可範囲（§6）と、受け入れ確認の環境（§5）。

台帳は `backlog-sweep` §2 の表を兼ねる（列の定義は向こうが持つ）。steward 用に次の列を足す。

| 列                     | 内容                                                                                                               |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 子の識別               | threadId とリンク、worktree のパス、branch、base の full SHA                                                       |
| 報告区分               | `dev-progress-report` の状態語彙（判断待ち / CI待ち / 作業中 / 完了 / 停止）。`backlog-sweep` の「状態」とは別の軸 |
| 再開を起こす主体と事象 | 例: 子の完了通知、`watch_pull_request` の CI 完了、`schedule_task` の心拍、人間の返答                              |

「触るファイル」には、ブラウザで検証する行に限り `browser:<product>` を仮想ファイルとして入れる。同じ仮想ファイルを持つ行は `orchestrator-worker` §3 の直列ルールで並ぶ。ブラウザを使わない行は並列のまま。

### 先書き

台帳は作業の区切りではなく、子の起動・push・マージ・デプロイの前後に更新する。起動前に行と base を書き、起動直後に threadId を書く。後継の steward は他人の子を `task_status` で読めないので、台帳の threadId から `t3_thread_read` / `t3_thread_wait` で拾い直す。台帳に無い子は、後継からは存在しないものになる。

文脈が重くなったら、区切りごとに要約を台帳へ寄せ、生ログや diff は子に持たせる。それでも重ければ §8 の交代へ進む。

外側の triage や担当bot の操作、人間の手動操作で子が settle されていたら、それは行方不明ではなく片付け済みとして扱う。ただし台帳の行を閉じるのは、§5 の受け入れ（完了報告の受領と検証）が済んだ場合だけ。未受け入れなら行は残し、一覧から消えた子は台帳の threadId で settled の状態を確認して、成果と残作業を確かめる。settle されたことだけを理由に、同じ仕事の子を再起動しない。

## 3. 再開条件（心拍）

子の完了では steward が起きるが、外部の待ちが解けたときは何も起こらない。待ちを作る前に、台帳の該当行へ「再開を起こす主体と事象」を割り当てる。

| 待つもの           | 再開させる手段                                                      |
| ------------------ | ------------------------------------------------------------------- |
| CI・レビューの完了 | `watch_pull_request`。PR の見張り方の手順は `babysit-pr` を参照する |
| 子の完了           | 子の完了通知                                                        |
| 上記以外の外部状態 | `schedule_task` で心拍を置く。間隔は待つ対象の変化の速さで決める    |
| 人間の判断         | 返答。割り当てる主体は人間                                          |

全行が判断待ちや外部待ちで、実行可能な行が無いときの idle は欠陥ではなく正しい停止。分配の良し悪しは「実行可能になった行が放置された時間」で測る。

steward は自分自身を完了や区切りで settle しない（`t3-stack` と同じ。子の settle は §5）。settle するのは役割の終了と後継への引き継ぎのときだけ。

## 4. 子の起動と依頼文

子は `delegate_task`（`runtimeMode: "auto"` を明示）で起動する。判定・分割・tier・昇格は `orchestrator-worker`、worktree と権限の共通決まりは `t3-stack` に従う。依頼文は自己完結で書き、次を must で入れる。

- envelope の4欄: `source_role` / `target_role` / `task_id`（台帳の ID）/ `report_contract`。
- 役割と台帳の場所（「steward 配下の子。台帳は `<path>`。`t3-steward` の steward が親」）。完了通知、`freshContext` での再送、交代後の最初のターンでも、役割と台帳の場所が文面だけで分かるようにする。
- base の full SHA と `origin/<branch>`。子は開始直後に `git rev-parse HEAD` で照合し、ずれていれば `BLOCKED` で返す。`delegate_task` の worktree は親の commit を起点にし、baseRef を指定できないため、この照合が base の鮮度を保証する唯一の手段になる。
- 新しい worktree の setup 実行済みの確認（`t3-stack`「worktree のセットアップ」）。
- scratch の置き場 `tmp/<task_id>/`。
- 報告契約は `t3-stack`「ワーカー側の決まり」の報告契約を指す。
- ブラウザを使う行は、使う product のプロファイルと、`browser:<product>` の行であること。

日本語の報告文の形式（`dev-progress-report`）は人間向けだけに使う。子から steward への報告は機械契約で、`dev-progress-report` を使わない。

## 5. 検証・受け入れ

- steward 自身はブラウザを操作しない。chrome-devtools は最初に掴んだプロファイルをセッション中保持するので、常駐 steward が一度開くとロックが外れず、子が使えなくなる。実際の操作は Verifier に切り、steward は保存された証拠を読んで判定だけする。
- Verifier は役ではなく、`report_contract: DONE` で起動した Worker。証拠収集だけをさせ、合否は steward が判定する（作者でない steward が判定するので self-review の禁止を満たす）。
- 枠の管理: 検証が終わった子は、証拠のパスを受け取ったあと steward が settle する。settle するまでブラウザの枠は空かない（idle ではロックが外れない。実測は `t3-stack` のブラウザ節）。掴めなかった子は `BLOCKED(browser busy)` で返す。待機・再試行・既定プロファイルや `--isolated` への切り替えはさせない。待機している子はブラウザを握らずにターンを閉じ、枠が空いたら steward が同じスレッドへ追送して再開させる。
- 受け入れ確認の環境は product ごとに台帳へ書く。localhost／プレビュー／stg のどれか、origin も含める。develop から stg へ流れる product ではマージ前に stg を確認できない。localhost は別途ログインが要り、dev server のポートも競合しうる。production での確認は読み取りだけを must にする。
- 子の受け取り検証は `orchestrator-worker` §5 に従う。子の `DONE` は未検証の申告として扱い、SHA と差分を自分で照合する。
- 子の settle は steward の責任: 受け入れた子は、完了報告を受領し、検証と受け入れを終えたら steward が settle する。外側の triage は steward 配下の子を対象にしない（台帳を読めるのは steward だけのため）ので、steward が settle しなければ子は一覧に残り続ける。

## 6. レビューとマージ

- verdict が要るレビュー（マージ条件の blocking 0）は、`orchestrator-worker`「verdict review の起動と受理」の `codex exec -s read-only` を既定にする。T3 スレッドへの読み取り専用依頼は、実行時に強制されないので advisory 止まり。
- 差し戻しは同じ子へ `t3_thread_send`。再レビューも新規セッションの verdict 経路（`codex exec -s read-only`）で行い、固定する SHA は修正後の `HEAD` に取り直す。prompt に前回の指摘と反論を書く。T3 スレッド（`delegate_task`）の再レビューは advisory で、マージ gate の承認にならない。公式の「小さなレビュー指摘は親が直す」は採らず、差し戻して子に直させる（公式より優先）。
- steward のマージ権限は担当bot と同じ条件（`t3-stack`「マージとデプロイ」）: 人間の常設許可か、そのタスクでの条件付き許可があり、かつ verdict の承認で blocking 0、bot のレビューを含むコメントを確認済み、CI 緑、CLEAN。`--admin` は使わない。
- 反映の範囲: stg への反映は常設の許可、production は都度人間の承認。product ごとに、この範囲を台帳の冒頭へ明記する。
- PR の作成は `file-pr` に従う。tstack の `full-send` は verdict gate（`codex exec -s read-only`、CI、CLEAN）と衝突するので、人間が明示したときだけ使う。

## 7. 報告

steward から人間への報告は `dev-progress-report` の形式で、台帳へのリンクを「詳細」に置く。担当bot 経由の依頼でも同じ。

## 8. 引き継ぎ・交代

- 引き継ぎ手段は `t3-stack`「スレッド間の連携と引き継ぎ」が持つ。外部の資料を作る前に `fork`（同名の後継）で足りるかを確かめる。別プロセス・別セッションへ渡すときは `takeover` を参照する。
- 交代する側は、台帳の「現在の owner」を先に書き換える。あわせて新旧の environmentId と threadId を担当bot へ伝え、外側 triage の保護リストを更新させる（交代中は新旧の両方が保護対象になる）。旧スレッドは旧と分かる名前に変え、settle してから archive する。同じ名前の steward が2本見える期間を作らない。
- steward が止まったときの代行は、Codex の Steward（handoff 専用）ではなく Codex の Architect（`orchestrator-worker` の tier 表）として起動する。
- 停止を見つける役は steward 自身ではなく外側（担当bot、または別プロバイダのセッション）に置く。
