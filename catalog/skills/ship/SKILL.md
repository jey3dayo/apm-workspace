---
name: ship
description: >-
  実作業の依頼で変更を終えて最終報告を書く前、commit / push / PR / deploy に進むとき、
  または「出荷して」「PR まで出して」と言われたときに、polish → full gate → 独立レビュー →
  commit → push → PR → CI → PR レビュー指摘の出荷を、repo ごとに許された範囲まで機械的に進める。
argument-hint: "[commit | push | pr]"
---

# Ship

仕上がった変更を**出荷**する。各工程の中身は下の表の担当が持つ。ここにあるのは、どこまで進めるか、どの順序で進めるか、どこで止めるかだけ。

## 1. 許可と終点を決める

**許可**（どこまで進めてよいか）は、上から順に最初に当たったもので決める。

1. 引数か依頼文が範囲を名指ししている（`pr` / 「PR まで」、`commit` など）→ その範囲。引数なしの `/ship` をユーザーが直接起動した → PR まで（自分の fork では push まで。`gh pr create` は既定で上流へ PR を作る）
2. GitHub remote が無い、または `gh` が使えない → 独立レビューまで進め、commit の案を出して止める
3. 自分が owner で fork ではない repo（`gh repo view --json owner,isFork` の `owner.login` が `gh api user -q .login` と一致し、`isFork` が `false`）→ PR まで。global AGENTS.md の停止・確認ポリシーが、この範囲を常設の依頼として扱う
4. それ以外（組織の repo、自分の fork など）→ 独立レビューまで進め、commit / push / PR の案を出して止める

**終点**（許可の範囲の最後の工程）は、repo の AGENTS.md が出荷の手順を定めていればそれに読み替える。定めが無ければ §2 の表のとおりで、PR の後に CI まで見る。終点は許可を広げない（deploy は終点の読み替えでだけ到達する）。

- 完了条件: 採用した許可の段と終点を1行で言える

## 2. 順に進める

| 工程            | 担当                                                                                                                                                                                                                                                                               | 次へ進む条件                                                           |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| polish          | `polish`（base-ref、自分の変更ファイル、変更の意図を引数で渡す）                                                                                                                                                                                                                   | 報告を受け取った。削除候補は親が判断する                               |
| full gate       | repo 定義の `check` / `test` / `ci` / `verify`。task が無く lefthook だけなら push 時の pre-push を gate とし、ここは該当なしと報告する                                                                                                                                            | green                                                                  |
| 独立レビュー    | 非軽微な変更だけ。model・起動経路・verdict の受理条件は `orchestrator-worker` の「Reviewer の tier」に従う。commit 前なので入力は適用元 `HEAD` の SHA とレビュー対象 diff の checksum で固定する。受理条件をすべて満たした verdict で判定し、advisory はこの工程の通過根拠にしない | 受理した verdict が approve で、blocking 指摘ゼロ（指摘対応は最大3回） |
| branch 確認     | default branch 上なら、repo の AGENTS.md が直接 commit を定めているか                                                                                                                                                                                                              | 定めがある、または default branch 外                                   |
| commit          | `atomic-commit`（自分の変更ファイルと意図を引数で渡す）                                                                                                                                                                                                                            | 意図した commit が揃い、保留が無い                                     |
| push            | `git push`（upstream 未設定なら `-u`）。lefthook の pre-push はここで走る。送り先が初回の branch か fork のときは、`push.followTags` が送り先に無い annotated tag も運ぶので、先に `git push --dry-run` で送る ref を確かめ、意図しない tag があれば `--no-follow-tags` を付ける   | hook を含めて成功                                                      |
| PR              | `gh pr create`。本文は global AGENTS.md「issue / PR 本文の扱い」                                                                                                                                                                                                                   | PR URL を得た                                                          |
| CI              | `gh pr checks --watch`                                                                                                                                                                                                                                                             | 全 check が pass                                                       |
| PR レビュー指摘 | `gh-address-comments`（PR を引数で渡す）と `pr-followup`。CI 完了時点で付いている指摘（未解決スレッド、会話コメント、レビュー本文。bot を含む。範囲は `pr-followup` §1）を対象にする                                                                                               | `pr-followup` §1〜§4 の完了条件                                        |

差分を書き換えた工程（polish、削除候補の削除、レビュー指摘の修正）の後は、full gate から回し直す。

独立レビューの blocking 指摘が、既存の挙動で依頼範囲外と判断できるときは、根拠を添えて todo に移し、同じ reviewer へ再提示して非 blocking へ再分類させる。再分類されなければ §3 で止める。

ship の中では actionable な指摘をすべて対象にし、どれを直すかは聞かない。確認待ち（`pr-followup` §1）が出たら §3 で止める。修正の積み方、返信、resolve は `pr-followup` に従う。この返信と resolve の許可は `pr-followup` の起動条件に従う。指摘への対応と full gate から CI までの反復は最大3回とし、超えたら §3 で止める。

- 完了条件: 終点の工程まで「次へ進む条件」を満たした

## 3. 止めるとき

機械的に進められない地点に着いたら、そこまでの結果を報告して止める。

- 自分の変更だけを切り出せない: herdr 上なら `herdr` で同じツリーの agent を特定し、持ち主へ切り分け（どちらが先に commit するか、混在した hunk はどちらのものか）を依頼する。返答か `git status` の変化を自分で確かめるまで出荷を止める。持ち主が特定できない、または herdr の外なら止める
- default branch 上で直接 commit の定めが無い: branch を切る案を出して止める
- full gate・CI の失敗が、判断を挟まないと直らない。レビュー指摘に確認待ち（`pr-followup` §1）がある。CI の失敗は `gh-fix-ci` で原因と修正案を出したところで止める
- global AGENTS.md の停止・確認ポリシーの条件に当たる

PR のマージは出荷に含めない。依頼を受けてから始める。

## 4. 報告

工程ごとに1行の表で返す。

| Step | 工程 | 状態 | 証拠 |
| ---- | ---- | ---- | ---- |

- 状態は `completed` / `skipped`（理由）/ `blocked`（止めた条件）/ `not-in-scope`（範囲外）
- 証拠は commit SHA、PR URL、CI の結果、deploy の検証結果など、次の人が辿れるもの
- 止めた場合は、再開に要る判断を1行で書く
