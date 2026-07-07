---
name: atomic-commit
description: 変更ファイルを論理的な最小単位でグループ化し、git log のスタイルに合わせた Conventional Commits 形式でグループごとに個別コミットする。ユーザーが commit / push の実行（「コミットして push」`commit and push` など）を依頼したとき、「最小単位でコミット」`atomic commit` を求めたとき、または dotenvx-managed `.env.*` を含むコミット計画で使用する。push 単独、PR 作成、ブランチ作成、GitHub 公開は扱わず、コミット分割とメッセージ作成に範囲を絞る。
---

# Atomic Commit

変更ファイルを論理的な最小単位に分割し、グループごとに順番にコミットする。

git コマンドは raw `git` を基本にする。

このスキルはコミット分割とメッセージ作成だけを担当する。worktree の作成・切替・削除や、隔離 workspace が必要かの判断は `using-git-worktrees` / `git-worktree` に委ねる。

## ワークフロー

### 1. 変更状況の把握

```bash
git status
git diff --name-only
git diff --cached --name-only
git diff -- <non-env paths>
```

- staged 済みの変更と untracked ファイルも計画対象に含める。staged 済みでも論理グループと一致しない場合はグループを組み直す
- `.env`, `.env.*`, 認証情報, secret が含まれる疑いのあるファイルは差分本文を表示せず、「環境ファイルの安全検査」セクションに従って扱いを決める

### 2. コミットスタイルの確認

```bash
git log --oneline -10
```

直近ログから Conventional Commits（`feat:`, `fix:`, `chore:`, `docs:`, `build:`, `test:` 等）の type / scope / 言語の傾向を確認し、メッセージをそのスタイルに合わせる。

### 3. ファイルのグループ化

変更ファイルを **論理的なまとまり** でグループ化する。グループ化の基準：

| 優先度 | 基準                     | 例                                         |
| ------ | ------------------------ | ------------------------------------------ |
| 高     | 機能・目的の一致         | 同じ機能追加に関わる複数ファイル           |
| 高     | 変更の種類               | 設定変更のみ、テストのみ、ドキュメントのみ |
| 中     | ディレクトリ・モジュール | 同じモジュール配下のファイル               |
| 低     | ファイルタイプ           | 同種ファイルのまとめ（最終手段）           |

- 1グループ = 1コミット。関係のないファイルは別グループにする
- 1ファイルに無関係な論理変更が混在する場合は hunk 単位に分割して別グループに割り当てる。対話入力が使える環境では `git add -p`、使えない環境では対象 hunk だけの patch（標準の `a/` `b/` ヘッダー形式）を作り `git apply --cached <patch>` で stage する
- グループ間に依存がある場合は、依存される側（設定・型定義・ユーティリティなど）を先にコミットする
- 未完成・意図が判断できない変更は別グループとして保留し、ユーザーに確認する
- `.env.*` は「環境ファイルの安全検査」を通過したものだけ、該当する論理グループに入れる

### 4. コミットタイプの選択

| type       | 用途                               |
| ---------- | ---------------------------------- |
| `feat`     | 新機能追加                         |
| `fix`      | バグ修正                           |
| `chore`    | ビルド・設定・雑務（機能変更なし） |
| `docs`     | ドキュメントのみの変更             |
| `build`    | ビルドシステム・依存関係の変更     |
| `test`     | テストの追加・修正                 |
| `refactor` | リファクタリング（機能変更なし）   |

スコープが明確な場合は `chore(scope):` のように付与する。

### 5. グループごとにコミット

各グループに対して以下を実行：

```bash
# ファイルをステージング
git add <file1> <file2> ...

# コミット（HEREDOC 形式）
git commit -m "$(cat <<'EOF'
<type>(<scope>): <概要>
EOF
)"
```

- メッセージは変更内容の簡潔な記述のみ。署名・フッターは付けない
- commit hook が失敗した、またはファイルを書き換えた場合は停止して報告する。`--no-verify` でのバイパスはユーザーの明示指示がない限り行わない

### 6. 完了確認

```bash
git status
git log --oneline -<グループ数>
```

意図したコミットがすべて揃い、残っている dirty ファイルが「意図的に除外したもの」だけであることを確認して報告する。除外したファイルがあれば、ファイル名と除外理由を併記する。

## 環境ファイルの安全検査

dirty な `.env.*` は自動除外せず、dotenvx-managed かを値を表示せずに判定する。repo の source of truth になり得るためである。

```bash
# dotenvx 管理ファイルかを値なしで判定する
rg -n '^(DOTENV_PUBLIC_KEY=.*|[A-Z0-9_]+=encrypted:.*)' --replace '<dotenvx-managed>' .env.* 2>/dev/null
```

| 判定結果                                       | 扱い                                                                  |
| ---------------------------------------------- | --------------------------------------------------------------------- |
| `DOTENV_PUBLIC_KEY` または `encrypted:` 値あり | dotenvx-managed。下の平文 secret 検査を通過すればコミット対象に入れる |
| raw `.env` / dotenvx-managed と判定できない    | raw secret の可能性があるため stage しない                            |
| 平文 secret 候補を含む（下の検査で検出）       | stage せず、ファイル名と key 名だけを報告して停止する                 |

dotenvx-managed と判定できても、追加差分に平文 secret 候補が混入していないか値を出さずに検査する：

```bash
# 追加された平文 secret 候補を key 名だけで検出する
git diff -U0 -- .env.* \
  | rg '^\+[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH)[A-Z0-9_]*=' \
  | rg -v '^\+[A-Z0-9_]+=encrypted:' \
  | rg -n '^\+([^=]+)=.*' --replace '$1=<plain-secret-candidate>'
```

この検査は `encrypted:` 値の行を許可し、平文 secret らしき値が混入した行だけを止める。出力が 1 行でもあれば、その `.env.*` は stage しない。

報告時は、どの段階でも secret の値・差分本文を表示せず、ファイル名・管理方式・差分の有無だけを伝える。
