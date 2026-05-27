---
name: atomic-commit
description: |
  変更ファイルを論理的な最小単位でグループ化し、グループごとに個別コミットする。
  git log のスタイルを参照して Conventional Commits 形式でメッセージを自動生成する。
  「最小単位でコミット」「触ったファイルをまとめてコミット」「atomic commit」や dotenvx-managed `.env.*` を含むコミット計画で使用する。
---

# Atomic Commit

変更ファイルを論理的な最小単位に分割し、グループごとに順番にコミットする。

## ワークフロー

### 1. 変更状況の把握

```bash
rtk git status
rtk git diff --name-only
rtk git diff -- <non-env paths>
```

`.env`, `.env.*`, 認証情報, secret が含まれる疑いのあるファイルは、この時点で差分本文を表示しない。

dirty な `.env.*` を見つけたら、自動除外せず dotenvx-managed か安全に検査する。値や差分本文は表示しない。

```bash
# dotenvx 管理ファイルかを値なしで判定する
rtk proxy rg -n '^(DOTENV_PUBLIC_KEY=.*|[A-Z0-9_]+=encrypted:.*)' --replace '<dotenvx-managed>' .env.* 2>/dev/null
```

`DOTENV_PUBLIC_KEY` または `encrypted:` 値が見つかる `.env.*` は dotenvx-managed とみなす。該当する場合は、ファイル名・dotenvx 管理であること・dirty であることだけを伝え、通常の変更ファイルとしてコミット計画に入れる。

dotenvx-managed と判定できても、追加差分に平文 secret 候補が混入していないか値を出さずに検査する。検出したらコミット計画へ入れず、ファイル名と key 名だけを報告して停止する。

```bash
# 追加された平文 secret 候補を key 名だけで検出する
rtk proxy git diff -U0 -- .env.* \
  | rtk proxy rg '^\+[A-Z0-9_]*(SECRET|TOKEN|PASSWORD|PRIVATE|CREDENTIAL|DATABASE_URL|AUTH)[A-Z0-9_]*=' \
  | rtk proxy rg -v '^\+[A-Z0-9_]+=encrypted:' \
  | rtk proxy rg -n '^\+([^=]+)=.*' --replace '$1=<plain-secret-candidate>'
```

この検査は `encrypted:` の値がある行を許可し、誤って平文 secret っぽい値が混入した行を止めるためのもの。出力が 1 行でもあれば、その `.env.*` は stage しない。

### 2. コミットスタイルの確認

```bash
rtk git log --oneline -10
```

Conventional Commits 形式（`feat:`, `fix:`, `chore:`, `docs:`, `build:`, `test:` 等）を確認する。

### 3. ファイルのグループ化

変更ファイルを **論理的なまとまり** でグループ化する。グループ化の基準：

| 優先度 | 基準                     | 例                                         |
| ------ | ------------------------ | ------------------------------------------ |
| 高     | 機能・目的の一致         | 同じ機能追加に関わる複数ファイル           |
| 高     | 変更の種類               | 設定変更のみ、テストのみ、ドキュメントのみ |
| 中     | ディレクトリ・モジュール | 同じモジュール配下のファイル               |
| 低     | ファイルタイプ           | 同種ファイルのまとめ（最終手段）           |

**1グループ = 1コミット**。関係のないファイルは別グループにする。

dotenvx-managed `.env.*` は、repo の source of truth になり得るため自動除外しない。安全な検査で dotenvx-managed と判定でき、平文 secret 候補が検出されないものだけ、値や secret 断片を表示しないまま該当する論理グループに入れる。raw `.env`、dotenvx-managed と判定できない `.env.*`、平文 secret 候補を含む `.env.*`、認証情報、secret が含まれる疑いのあるファイルはコミット対象にしない。

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
rtk git add <file1> <file2> ...

# コミット（HEREDOC 形式）
rtk git commit -m "$(cat <<'EOF'
<type>(<scope>): <概要>
EOF
)"
```

全グループのコミット完了後、`rtk git log --oneline -5` で結果を確認する。

## 注意事項

- raw `.env`、認証情報、secret が含まれる疑いのあるファイルはコミットしない
- dirty な `.env.*` を見つけたら dotenvx-managed か検査してからコミット計画を作る
- dotenvx-managed `.env.*` は repo の source of truth になり得るため、自動除外しない
- `encrypted:` 値の行は dotenvx 管理として扱ってよい
- dotenvx-managed `.env.*` でも、追加差分に平文 secret 候補があれば stage せず停止する
- dotenvx-managed `.env.*` を確認するときは、ファイル名・管理方式・差分の有無だけを伝える
- dotenvx-managed と判定できない `.env.*` は raw secret の可能性があるため stage しない
- 未完成の変更は別グループとして扱い、ユーザーに確認する
- `rtk` プレフィックスを全 git コマンドに付ける
