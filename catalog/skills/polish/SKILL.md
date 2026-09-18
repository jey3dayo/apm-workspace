---
name: polish
model: sonnet
disable-model-invocation: true
description: PR を出す前に、base との diff で追加・変更した行を global AGENTS.md / CLAUDE.md の開発原則へ揃える（コメント圧縮・テストの実装詳細依存の除去・型逃げ・エラー握りつぶし・過剰な抽象化・不要ファイル）。
argument-hint: "[base-ref]"
---

# Polish

PR 前に、このブランチで**追加・変更した行だけ**を観点表の全行へ照らして直す。原則の本文は global `AGENTS.md` / `CLAUDE.md` の「開発原則」「禁止事項」「ファイル操作原則」が正本で、ここには写さない。判断に迷ったらそちらを読む。

lint / format / test のループは対象外（DoD が持つ）。再利用・効率・altitude（root cause の深さ）は built-in `/simplify` が持つ。base より前から存在する行も対象外で、diff の外に気づいた問題は報告に列挙するだけで触らない。

## 手順

### 1. 範囲確定

base は上から順に解決し、最初に当たった段を採る。trunk 候補は `git symbolic-ref refs/remotes/origin/HEAD` が指す branch と `origin/develop` / `origin/main` / `origin/master` のうち `git rev-parse --verify` が通るもの。

1. 引数
2. `gh pr view --json baseRefName -q .baseRefName`（このブランチの open PR）
3. HEAD が trunk 候補そのものに居るなら `@{upstream}`、upstream 未設定なら `HEAD`
4. それ以外は `git rev-list --count origin/<候補>..HEAD` が最小の候補。分岐元に最も近い trunk がこれで出る

順序が効く: develop 上に居るときに 4 を先に当てると、ahead が 0 の develop を飛ばして `origin/main` が選ばれ、develop の既存コミットまで対象に入る。

対象は merge-base 起点の diff で、未コミットの変更まで含める。PR 前は commit していない行も polish 対象である。

```sh
git diff "$(git merge-base <base> HEAD)"
```

追加行（`+`）と削除行（`-`）を hunk ごとに把握する。`git diff` は untracked を映さないので、`git status --porcelain` の `??` も対象ファイルへ加える（step 2 の「不要ファイル」観点がこれを見る）。

- 完了条件: base ref が確定し、対象ファイル一覧が取れている。diff が空なら「対象なし」と報告して終了する

### 2. 観点表を全行適用

各観点について、diff の追加行**全件**を判定し、該当箇所を直す。1 観点ずつ diff を読み直す。

| 観点             | 検出（追加行に対して）                                                                                                 | 直し方                                                                                                       |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| コメント         | 追加・変更したコメント全件。名前・型・構造で伝わる内容、処理の見出し、検討履歴、How の説明                             | 削除。残すなら Why / What を 1〜2 行へ。検討履歴は PR 本文へ                                                 |
| テスト           | 追加・変更したテスト全件。呼び出し回数・順序・version の固定、実装をなぞるだけの assertion、可逆で低影響な変更の鏡写し | 振る舞い（入力→出力、業務ルール、外部契約）の assertion へ置換。鏡写しは削除。固定が契約なら根拠をテスト名へ |
| lint disable     | `eslint-disable` / `biome-ignore` / `@ts-ignore` / `@ts-expect-error` / `noqa` / `#[allow(` の追加                     | 設定ファイル側の rule 調整へ移す。その 1 箇所だけが真に例外なら理由を添えて残す                              |
| 型逃げ           | `: any` / `<any>` / `as X`（`as const` は除く）/ 非 null `!` の追加                                                    | narrowing か型定義の修正で型を導く                                                                           |
| エラー握りつぶし | 空 `catch`、`.catch(() => {})`、`except: pass`、結果を捨てる `try`                                                     | 境界で処理し、呼び出し元へ意味のある形で伝播                                                                 |
| 過剰な差分       | 呼び出し元が 1 つの helper / option 引数、未使用 export、PR 目的と無関係な drive-by 変更、将来用途だけの抽象化・設定   | inline 化 or 削除。無関係な改善は別 PR へ切り出して diff から外す                                            |
| 不要ファイル     | 新規 `*.md`（要求なし）、`tmp/`、`plans/`                                                                              | 削除。恒常的に生成されるなら `.gitignore`                                                                    |

観点を足すときはこの表に 1 行追加する。手順と完了条件は変えない。

- 完了条件: 表の全行について、diff の追加行全件を判定済み。判定に迷った箇所は直さず報告へ回す

### 3. 軽い確認

touched file の format と、変更箇所に関連するテストを実行する（DoD の「実装中・小さな修正後」の粒度）。full gate は Orchestrator / ユーザーが PR 前に別途回す。

### 4. 報告

- base ref（解決した段）と対象ファイル数
- 観点ごとの件数: 直した / 残した（残した理由を 1 行）
- 判定に迷い触らなかった箇所
- diff の外で気づいた既存の違反（触っていない）
- 回帰テストの red → green 確認は本スキルでは検証できない。未確認ならその旨を 1 行

commit / push / PR 作成は行わない。commit は `atomic-commit` に渡す。
