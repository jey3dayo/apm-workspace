# Existing PR Detection - 既存PR検出ロジック

既存PRの検出、対応方針決定、更新処理の詳細仕様です。

## 概要

同じブランチに既存のPRがある場合、重複作成を防ぎ、適切な対応（更新/新規作成/中止）を選択します。

## Phase 3.5: 既存PR検出フロー

```
コミット作成完了
    ↓
gh pr list --head {branch} で既存PR確認
    ↓
OPEN/DRAFT PRが見つかった？
    ↓ Yes
対応方針決定（オプション/対話的）
    ↓
PR更新 or 新規作成 or 中止
```

## 既存PR検出

### 実装

```python
def check_existing_pr(branch_name):
    """現在のブランチに既存のPRがあるか確認"""

    print(f"🔍 既存PRを確認中: {branch_name}")

    try:
        result = subprocess.run(
            ["gh", "pr", "list",
             "--head", branch_name,
             "--json", "number,title,url,state"],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            print(f"⚠️  PR確認エラー: {result.stderr}")
            return None

        if not result.stdout.strip():
            print("ℹ️  既存PRなし")
            return None

        # JSON解析
        prs = json.loads(result.stdout)

        # OPENまたはDRAFT状態のPRのみ対象
        open_prs = [pr for pr in prs if pr['state'] in ['OPEN', 'DRAFT']]

        if open_prs:
            pr = open_prs[0]  # 最新のPRを返す
            print(f"✅ 既存PR検出: #{pr['number']} - {pr['title']}")
            return pr
        else:
            print("ℹ️  既存PRなし（OPEN/DRAFTのみ対象）")
            return None

    except json.JSONDecodeError as e:
        print(f"⚠️  JSON解析エラー: {e}")
        return None
    except Exception as e:
        print(f"⚠️  予期しないエラー: {e}")
        return None
```

### 検出対象

| PR状態 | 検出対象              |
| ------ | --------------------- |
| OPEN   | ✅ 対象               |
| DRAFT  | ✅ 対象               |
| MERGED | ❌ 対象外（新規作成） |
| CLOSED | ❌ 対象外（新規作成） |

### 理由

## 対応方針決定

### 決定ロジック

```python
def decide_pr_action(existing_pr, options):
    """既存PRに対する対応方針を決定"""

    # オプション1: --check-only（確認のみ）
    if options.get('check_only'):
        if existing_pr:
            print(f"ℹ️  既存PR: #{existing_pr['number']} - {existing_pr['title']}")
            print(f"   URL: {existing_pr['url']}")
            print(f"   状態: {existing_pr['state']}")
        else:
            print("ℹ️  既存PRなし")
        return 'abort'

    # オプション2: --force-new（強制新規作成）
    if options.get('force_new'):
        print("🆕 --force-new オプション: 新規PR作成を実行")
        return 'create'

    # ケース1: 既存PRがない
    if not existing_pr:
        return 'create'

    # ケース2: 既存PRがある
    print(f"\nℹ️  既存のPR検出:")
    print(f"   #{existing_pr['number']}: {existing_pr['title']}")
    print(f"   URL: {existing_pr['url']}")
    print(f"   状態: {existing_pr['state']}")

    # オプション3: --update-if-exists（自動更新）
    if options.get('update_if_exists'):
        print("🔄 --update-if-exists オプション: PR更新を実行")
        return 'update'

    # ケース3: 対話的選択
    print("\n既存のPRが見つかりました。どうしますか？")
    print("1. 更新 - 既存PRのタイトルと本文を更新")
    print("2. 新規作成 - 新しいPRを作成")
    print("3. キャンセル - 処理を中止")

    while True:
        choice = input("選択してください (1-3): ").strip()
        if choice == "1":
            return 'update'
        elif choice == "2":
            return 'create'
        elif choice == "3":
            return 'abort'
        else:
            print("⚠️  無効な選択です。1-3を入力してください。")
```

### オプション一覧

| オプション           | 動作         | 用途                 |
| -------------------- | ------------ | -------------------- |
| なし                 | 対話的選択   | 手動で判断したい場合 |
| `--check-only`       | 確認のみ     | PRの存在確認のみ     |
| `--force-new`        | 強制新規作成 | 既存PRを無視         |
| `--update-if-exists` | 自動更新     | CI/CD等での自動化    |

## PR更新処理

### 実装

```python
def update_pull_request(pr_number, pr_title, pr_body, current_branch, options):
    """既存のPRを更新"""

    print(f"📝 PR #{pr_number} を更新中...")

    # 1. リモートへプッシュ（コミットを追加）
    print(f"📤 {current_branch} をプッシュ中...")
    push_result = subprocess.run(
        ["git", "push", "origin", current_branch],
        capture_output=True,
        text=True
    )

    if push_result.returncode != 0:
        print(f"❌ プッシュ失敗: {push_result.stderr}")
        return None

    print("✅ プッシュ完了")

    # 2. PRのタイトル・本文を更新
    update_command = f"""gh pr edit {pr_number} \
        --title "{pr_title}" \
        --body "$(cat <<'EOF'
{pr_body}
EOF
)""""

    result = subprocess.run(
        update_command,
        shell=True,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        # PR URL取得
        pr_info = subprocess.run(
            ["gh", "pr", "view", str(pr_number), "--json", "url"],
            capture_output=True,
            text=True
        )

        if pr_info.returncode == 0:
            pr_data = json.loads(pr_info.stdout)
            pr_url = pr_data.get('url', '')
            print(f"✅ PR #{pr_number} の更新完了")
            print(f"   URL: {pr_url}")
            return pr_url
        else:
            print(f"✅ PR #{pr_number} の更新完了")
            return f"https://github.com/.../pull/{pr_number}"
    else:
        print(f"❌ PR更新エラー: {result.stderr}")
        return None
```

### 更新内容

| 項目           | 更新            | 保持    |
| -------------- | --------------- | ------- |
| タイトル       | ✅ 更新         | -       |
| 本文           | ✅ 更新         | -       |
| コミット       | ✅ 追加プッシュ | -       |
| ラベル         | -               | ✅ 保持 |
| レビュアー     | -               | ✅ 保持 |
| アサイニー     | -               | ✅ 保持 |
| マイルストーン | -               | ✅ 保持 |

### 理由

## ワークフロー統合

### メインフロー

```python
def create_or_update_pull_request(commit_groups, options):
    """既存PRがあれば更新、なければ作成"""

    # 現在のブランチ取得
    current_branch = get_current_branch()

    # Phase 3.5: 既存PR検出
    existing_pr = check_existing_pr(current_branch)

    # 対応方針決定
    action = decide_pr_action(existing_pr, options)

    # アクション実行
    if action == 'abort':
        print("❌ 処理を中止しました")
        return None

    elif action == 'update':
        # PR情報生成
        pr_title = generate_pr_title(commit_groups, options)
        pr_body = generate_pr_body_with_template(
            commit_groups, current_branch, options
        )

        # PR更新
        return update_pull_request(
            existing_pr['number'],
            pr_title,
            pr_body,
            current_branch,
            options
        )

    elif action == 'create':
        # 新規PR作成
        return create_new_pull_request(commit_groups, current_branch, options)
```

## エラーハンドリング

### gh CLI未認証

```python
if "authentication" in result.stderr.lower():
    print("\n❌ GitHub CLI未認証")
    print("\n💡 対処方法:")
    print("   1. gh auth login で認証")
    print("   2. gh auth status で状態確認")
    print("   3. GitHub Personal Access Tokenを設定")
    return None
```

### PR更新失敗

```python
if "Could not resolve to a PullRequest" in result.stderr:
    print("\n❌ PR更新失敗: PRが見つかりません")
    print("\n💡 考えられる原因:")
    print("   - PRが既にマージまたはクローズされている")
    print("   - PR番号が間違っている")
    print("   - リポジトリのアクセス権限がない")
    print("\n対処方法:")
    print("   1. gh pr list でPR一覧を確認")
    print("   2. 新規PRを作成: --force-new オプションを使用")
    return None
```

### ブランチ保護ルール違反

```python
if "protected branch" in result.stderr.lower():
    print("\n❌ プッシュ失敗: ブランチ保護ルール違反")
    print("\n💡 対処方法:")
    print("   - main/master への直接プッシュは禁止されています")
    print("   - 別のブランチを作成してください")
    print("   - または管理者に権限を確認してください")
    return None
```

## 使用例

### 対話的更新

```bash
/git-automation pr

# 実行結果:
# 🔍 既存PRを確認中: feature/auth
# ✅ 既存PR検出: #123 - Add authentication
#
# ℹ️  既存のPR検出:
#    #123: Add authentication
#    URL: https://github.com/org/repo/pull/123
#    状態: OPEN
#
# 既存のPRが見つかりました。どうしますか？
# 1. 更新 - 既存PRのタイトルと本文を更新
# 2. 新規作成 - 新しいPRを作成
# 3. キャンセル - 処理を中止
# 選択してください (1-3): 1
#
# 📤 feature/auth をプッシュ中...
# ✅ プッシュ完了
# 📝 PR #123 を更新中...
# ✅ PR #123 の更新完了
#    URL: https://github.com/org/repo/pull/123
```

### 自動更新

```bash
/git-automation pr --update-if-exists

# 実行結果:
# 🔍 既存PRを確認中: feature/auth
# ✅ 既存PR検出: #123 - Add authentication
# 🔄 --update-if-exists オプション: PR更新を実行
# 📤 feature/auth をプッシュ中...
# ✅ プッシュ完了
# 📝 PR #123 を更新中...
# ✅ PR #123 の更新完了
#    URL: https://github.com/org/repo/pull/123
```

### 強制新規作成

```bash
/git-automation pr --force-new

# 実行結果:
# 🆕 --force-new オプション: 新規PR作成を実行
# 📤 feature/auth をプッシュ中...
# ✅ プッシュ完了
# ✅ PR作成完了: https://github.com/org/repo/pull/124
```

### 確認のみ

```bash
/git-automation pr --check-only

# 実行結果（既存PRあり）:
# 🔍 既存PRを確認中: feature/auth
# ✅ 既存PR検出: #123 - Add authentication
# ℹ️  既存PR: #123 - Add authentication
#    URL: https://github.com/org/repo/pull/123
#    状態: OPEN

# 実行結果（既存PRなし）:
# 🔍 既存PRを確認中: feature/new-feature
# ℹ️  既存PRなし
```

## ベストプラクティス

### CI/CDでの自動化

```yaml
# .github/workflows/auto-pr.yml
name: Auto PR

on:
  push:
    branches-ignore:
      - main
      - master

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Create or Update PR
        run: |
          /git-automation pr --update-if-exists --title "Automated PR"
```

### 開発フロー

```bash
# 開発中: 既存PR確認
/git-automation pr --check-only

# 既存PRあり: 更新
/git-automation pr --update-if-exists

# 既存PRなし: 新規作成
/git-automation pr
```

## 制約事項

- 複数PR: 同じブランチに複数のOPEN PRがある場合、最新のものを使用
- 状態制限: OPEN/DRAFT状態のPRのみが更新対象
- 権限: PRの更新にはリポジトリへの書き込み権限が必要
- gh CLI: GitHub CLIの認証が必須
