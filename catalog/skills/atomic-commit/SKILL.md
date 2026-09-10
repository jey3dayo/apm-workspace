---
name: atomic-commit
model: sonnet
description: >
  ユーザーが「commit」「コミット」「残りコミット」「コミットして push」「最小単位でコミット」`atomic commit`
  などコミット実行を依頼したとき、または dotenvx-managed `.env.*` を含むコミット計画を依頼したときに使用する。
  push 単独、PR 作成、ブランチ作成は扱わず、コミット分割とメッセージ作成に範囲を絞る。
---

# Atomic Commit

変更ファイルを論理的な最小単位に分割し、1グループ = 1コミットで順番にコミットする。git コマンドは raw `git` を基本にする。

worktree の作成・切替・削除や、隔離 workspace が必要かの判断は `git-worktree` に委ねる。

## ワークフロー

### 1. 変更状況の把握

```bash
git status
git diff --name-only
git diff --cached --name-only
git diff -- <non-env paths>
```

staged 済みの変更と untracked ファイルも計画対象に含める。staged 済みでも論理グループと一致しない場合はグループを組み直す。

完了条件: すべての dirty / staged / untracked ファイルが計画対象として列挙され、`.env.*` と secret 疑いファイルは差分本文を見ずに「環境ファイルの安全検査」へ回されている。untracked と staged 済みの `.env.*`、サブディレクトリの `.env.*` も検査に回す。

### 2. コミットスタイルの確認

```bash
git log --oneline -10
```

直近ログから Conventional Commits（`feat:`, `fix:`, `chore:`, `docs:`, `build:`, `test:`, `refactor:` 等）の type / scope / 言語の傾向を確認し、メッセージをそのスタイルに合わせる。スコープが明確な場合は `chore(scope):` のように付与する。

### 3. ファイルのグループ化

変更ファイルを論理的なまとまりでグループ化する：

| 優先度 | 基準                     | 例                                         |
| ------ | ------------------------ | ------------------------------------------ |
| 高     | 機能・目的の一致         | 同じ機能追加に関わる複数ファイル           |
| 高     | 変更の種類               | 設定変更のみ、テストのみ、ドキュメントのみ |
| 中     | ディレクトリ・モジュール | 同じモジュール配下のファイル               |
| 低     | ファイルタイプ           | 同種ファイルのまとめ（最終手段）           |

- 1ファイルに無関係な論理変更が混在する場合は hunk 単位に分割して別グループに割り当てる。対話入力が使える環境では `git add -p`、使えない環境では対象 hunk だけの patch（標準の `a/` `b/` ヘッダー形式）を作り `git apply --cached <patch>` で stage する
- グループ間に依存がある場合は、依存される側（設定・型定義・ユーティリティなど）を先にコミットする
- 未完成・意図が判断できない変更は別グループとして保留し、ユーザーに確認する

完了条件: すべての計画対象ファイル（安全検査を通過した `.env.*` を含む）がちょうど1つのグループまたは保留に属し、グループ間の依存順が決まっている。

### 4. グループごとにコミット

```bash
git add <file1> <file2> ...

git commit -m "$(cat <<'EOF'
<type>(<scope>): <概要>
EOF
)"
```

- stage は対象ファイルの明示指定のみ（`git add -A` / `.` / `-u`、`git commit -a` は使わない）
- commit 直前に `git diff --cached --name-only` の一覧がグループと完全一致することを確認する。グループ外の staged ファイルは `git restore --staged <file>` で外す
- メッセージは変更内容の簡潔な記述のみ。署名・フッターは付けない
- commit hook が失敗した、またはファイルを書き換えた場合は停止して報告する。`--no-verify` はユーザーの明示指示がない限り使わない

### 5. 完了確認

```bash
git status
git log --oneline -<グループ数>
```

完了条件: 意図したコミットがすべて揃い、残る dirty ファイルが意図的に除外したものだけであることを確認し、除外ファイルは名前と理由を併記して報告している。

## 環境ファイルの安全検査

dirty な `.env.*` は自動除外せず、dotenvx-managed かを判定する。repo の source of truth になり得るためである。検査・報告のどの段階でも secret の値・差分本文は表示せず、ファイル名・key 名・管理方式・差分の有無だけを扱う。

```bash
# dotenvx 管理ファイルかを値なしで判定する（出力に現れたファイルが managed）
/usr/bin/grep -lE '^(DOTENV_PUBLIC_KEY=|[A-Z0-9_]+=encrypted:)' .env.* 2>/dev/null
```

| 判定結果                                    | 扱い                                                                  |
| ------------------------------------------- | --------------------------------------------------------------------- |
| 上の出力にファイル名が現れる                | dotenvx-managed。下の平文 secret 検査を通過すればコミット対象に入れる |
| raw `.env` / dotenvx-managed と判定できない | raw secret の可能性があるため stage しない                            |
| 平文 secret 候補を含む（下の検査で検出）    | stage せず、ファイル名と key 名だけを報告して停止する                 |

dotenvx-managed と判定できても、追加差分に平文 secret 候補が混入していないか検査する：

```bash
# 1. 収集。tracked（staged + unstaged）と untracked の両方をファイルへ落とし、
#    収集側の終了コードを先に確かめる（空の出力を「secret なし」と読まないため）
raw=$(mktemp)
git diff -U0 HEAD -- ':(glob)**/.env.*' >"$raw" || { echo '収集失敗: 検査不成立'; exit 1; }
git ls-files --others --exclude-standard -z -- ':(glob)**/.env.*' \
  | xargs -0 -I{} git diff --no-index -U0 /dev/null {} >>"$raw"

# 2. 検査。平文 secret 候補の key 名だけを出す
/usr/bin/grep -E '^\+(export )?[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH|APIKEY|KEY|PAT|DSN)[A-Za-z0-9_]*=' "$raw" \
  | /usr/bin/grep -vE '^\+(export )?(DOTENV_PUBLIC_KEY=|[A-Za-z0-9_]+=[^A-Za-z0-9_]?encrypted:)' \
  | /usr/bin/grep -oE '^\+(export )?[^=]+=' \
  | cut -c2-
```

この検査は `encrypted:` 値の行を許可し、平文 secret らしき値が混入した行だけを止める。出力が 1 行でもあれば、その `.env.*` は stage しない。

**空の出力を「secret なし」の根拠にしない。** パイプは最終段の終了コードしか返さないため、収集側が失敗しても「一致なし」と区別がつかない（実測: producer を exit 128 にしても最終 exit は 0。`set -o pipefail` を足しても、一致なしという正常系と同じ 1 になるので区別できない）。上の手順が収集を先にファイルへ落とすのはこのためで、収集を確認できていない空出力は「検査不成立」として stage しない。`rg` ではなく `/usr/bin/grep` を絶対パスで呼ぶのも同じ理由——mise shim の `rg` は repo 外の cwd で解決に失敗し、stderr にだけエラーを出して stdout を空にする。

除外側で `DOTENV_PUBLIC_KEY` を明示的に落としているのは、これが dotenvx の**公開**メタデータであり、上の managed 判定そのものの根拠だからである。`KEY` を検出語群に入れた副作用で、正規の managed ファイルが自分の公開鍵で stage 禁止になるのを防ぐ。`encrypted:` の除外が引用符を許すのも同じ理由（`API_KEY="encrypted:..."` を平文と誤判定しない）。
