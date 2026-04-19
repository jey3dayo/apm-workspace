# PR Creation Flow - PR作成フロー詳細

Format→Commit→Push→PR作成の統合フローの詳細仕様です。

## フロー概要

```
Phase 1: フォーマッター検出
    ↓
Phase 2: フォーマット実行・変更確認
    ↓
Phase 3: インテリジェントコミット分割
    ↓
Phase 3.5: 既存PR検出・対応方針決定
    ↓
Phase 4: PR作成または更新
```

## Phase 1: フォーマッター検出

### 目的

プロジェクトの技術スタックを自動判定し、適切なフォーマッターを選択します。

### 実装

```python
from shared.project_detector import detect_formatter, detect_project_type

def detect_project_formatter():
    """プロジェクトのフォーマッターを自動検出"""

    # プロジェクト情報取得
    project = detect_project_type()
    formatters = detect_formatter()

    if not formatters:
        print("⚠️  フォーマッター未検出")
        return None

    # 最も信頼度の高いフォーマッターを選択
    formatter_info = formatters[0]

    # プロジェクトタイプに応じたコマンド構築
    if 'node' in project['stack']:
        pkg_manager = detect_package_manager()

        if formatter_info['type'] == 'script':
            # package.jsonのscript
            return f"{pkg_manager} run {formatter_info['command']}"
        else:
            # npx経由
            return f"{pkg_manager} exec {formatter_info['command']}"

    elif 'go' in project['stack']:
        # Go formatter
        return 'gofmt -w .'

    elif 'python' in project['stack']:
        # Python formatter
        return 'black .'

    elif 'rust' in project['stack']:
        # Rust formatter
        return 'cargo fmt'

    # その他
    return formatter_info.get('command')
```

### パッケージマネージャー検出

```python
def detect_package_manager():
    """Node.jsパッケージマネージャーを検出"""

    # ロックファイルから判定
    if os.path.exists('pnpm-lock.yaml'):
        return 'pnpm'
    elif os.path.exists('yarn.lock'):
        return 'yarn'
    elif os.path.exists('bun.lockb'):
        return 'bun'
    else:
        return 'npm'
```

## Phase 2: フォーマット実行

### 目的

コードを整形し、スタイル統一を図ります。

### 実装

```python
def execute_formatting(formatter_command, options):
    """フォーマッターを実行"""

    # スキップ判定
    if options.get('no_format'):
        print("📝 フォーマット処理をスキップします")
        return True

    # フォーマッター未検出時の処理
    if not formatter_command:
        print("⚠️  フォーマッターが検出されませんでした")
        print("💡 ヒント: package.json に format スクリプトを追加してください")

        if prompt_yes_no("手動でフォーマットコマンドを指定しますか？"):
            formatter_command = prompt_input("フォーマットコマンド: ")
        else:
            print("⏩ フォーマットをスキップして続行します")
            return True

    # フォーマット実行
    print(f"🎨 フォーマット実行: {formatter_command}")

    result = subprocess.run(
        formatter_command,
        shell=True,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✅ フォーマット完了")

        # 変更確認
        changed_files = get_git_status()
        if changed_files:
            print(f"📝 {len(changed_files)} ファイルが変更されました")
            for file in changed_files[:10]:  # 最初の10件のみ表示
                print(f"   - {file}")
            if len(changed_files) > 10:
                print(f"   ... 他 {len(changed_files) - 10} ファイル")

        return True
    else:
        print(f"❌ フォーマットエラー:")
        print(result.stderr)
        return False
```

### 変更確認

```python
def get_git_status():
    """変更ファイルリストを取得"""
    result = subprocess.run(
        ["git", "status", "--short"],
        capture_output=True,
        text=True
    )

    changed_files = []
    for line in result.stdout.strip().split('\n'):
        if line:
            # " M file.txt" → "file.txt"
            filepath = line[3:].strip()
            changed_files.append(filepath)

    return changed_files
```

## Phase 3: インテリジェントコミット分割

### 目的

変更内容を意味的なまとまりごとにコミットを作成します。

### 変更分類ロジック

```python
def create_intelligent_commits(options):
    """変更を適切な粒度でコミット"""

    if options.get('single_commit'):
        return create_single_commit()

    # 1. 変更ファイル取得
    files = get_git_status()

    # 2. 変更タイプごとにグループ化
    groups = {
        'format': [],      # フォーマットのみ
        'refactor': [],    # リファクタリング
        'feature': [],     # 機能追加
        'fix': [],         # バグ修正
        'test': [],        # テスト
        'docs': [],        # ドキュメント
        'config': [],      # 設定ファイル
        'deps': []         # 依存関係
    }

    for filepath in files:
        # Diffを取得
        diff = get_file_diff(filepath)

        # 変更タイプ分類
        change_type = classify_change(filepath, diff)
        groups[change_type].append(filepath)

    # 3. グループごとにコミット作成
    commit_groups = []
    for change_type, files in groups.items():
        if not files:
            continue

        # コミット作成
        commit_info = create_commit_for_group(change_type, files)
        commit_groups.append(commit_info)

    return commit_groups
```

### 変更タイプ分類

```python
def classify_change(filepath, diff_content):
    """ファイルと差分から変更タイプを判定"""

    # ファイルパスベースの分類
    if 'test' in filepath or 'spec' in filepath or filepath.endswith('.test.'):
        return 'test'

    if filepath.endswith(('.md', '.txt', '.rst', '.adoc')):
        return 'docs'

    if filepath in ['package.json', 'go.mod', 'requirements.txt', 'Cargo.toml']:
        return 'deps'

    if filepath.startswith('.') or 'config' in filepath.lower():
        return 'config'

    # Diff内容ベースの分類
    if is_formatting_only_change(diff_content):
        return 'format'

    if has_bug_fix_indicators(diff_content):
        return 'fix'

    if has_refactoring_indicators(diff_content):
        return 'refactor'

    # デフォルト: 機能追加
    return 'feature'

def is_formatting_only_change(diff):
    """フォーマットのみの変更か判定"""
    # 空白・インデント・改行のみの変更
    lines = diff.split('\n')
    for line in lines:
        if line.startswith('+') or line.startswith('-'):
            # 空白文字以外が含まれるか
            if line[1:].strip():
                content = line[1:].strip()
                # セミコロン、カンマ、括弧の位置変更のみ
                if not re.match(r'^[;,\(\)\{\}\[\]]+$', content):
                    return False
    return True

def has_bug_fix_indicators(diff):
    """バグ修正の指標を検出"""
    indicators = [
        r'fix', r'bug', r'issue', r'error',
        r'crash', r'fail', r'broken',
        r'resolve', r'correct'
    ]
    pattern = '|'.join(indicators)
    return bool(re.search(pattern, diff, re.IGNORECASE))

def has_refactoring_indicators(diff):
    """リファクタリングの指標を検出"""
    indicators = [
        r'refactor', r'rename', r'move',
        r'extract', r'inline', r'simplify',
        r'improve', r'clean'
    ]
    pattern = '|'.join(indicators)
    return bool(re.search(pattern, diff, re.IGNORECASE))
```

### コミット作成

```python
def create_commit_for_group(change_type, files):
    """グループに対してコミットを作成"""

    # ファイルをステージング
    for filepath in files:
        subprocess.run(["git", "add", filepath])

    # コミットメッセージ生成
    message = generate_commit_message_for_group(change_type, files)

    # コミット実行（署名なし）
    commit_command = f"""git commit -m "$(cat <<'EOF'
{message}
EOF
)""""

    result = subprocess.run(
        commit_command,
        shell=True,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print(f"✅ コミット作成: {message}")
    else:
        print(f"❌ コミット失敗: {result.stderr}")
        raise Exception("Commit failed")

    return {
        'type': change_type,
        'files': files,
        'message': message
    }
```

## Phase 3.5: 既存PR検出

詳細は [existing-pr-detection.md](./existing-pr-detection.md) を参照。

### 概要

```python
def handle_existing_pr_workflow(commit_groups, options):
    """既存PR検出とアクション決定"""

    # 現在のブランチ取得
    current_branch = get_current_branch()

    # 既存PR確認
    existing_pr = check_existing_pr(current_branch)

    # 対応方針決定
    action = decide_pr_action(existing_pr, options)

    return action, existing_pr, current_branch
```

## Phase 4: PR作成または更新

### 新規PR作成

```python
def create_new_pull_request(commit_groups, current_branch, options):
    """新規PRを作成"""

    # 1. ブランチ確認
    if current_branch in ['main', 'master', 'develop']:
        # 新規ブランチ作成
        if not options.get('branch'):
            branch_name = generate_branch_name(commit_groups)
            subprocess.run(["git", "checkout", "-b", branch_name])
            current_branch = branch_name
            print(f"🌿 新規ブランチ作成: {branch_name}")

    # 2. リモートへプッシュ
    print(f"📤 {current_branch} をプッシュ中...")
    push_result = subprocess.run(
        ["git", "push", "-u", "origin", current_branch],
        capture_output=True,
        text=True
    )

    if push_result.returncode != 0:
        print(f"❌ プッシュ失敗: {push_result.stderr}")
        return None

    # 3. PR情報生成
    pr_title = generate_pr_title(commit_groups, options)
    pr_body = generate_pr_body_with_template(commit_groups, current_branch, options)

    # 4. gh コマンドでPR作成
    pr_command = f"""gh pr create --title "{pr_title}" --body "$(cat <<'EOF'
{pr_body}
EOF
)""""

    if options.get('base'):
        pr_command += f" --base {options['base']}"

    if options.get('draft'):
        pr_command += " --draft"

    # PR作成実行
    result = subprocess.run(
        pr_command,
        shell=True,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        pr_url = result.stdout.strip()
        print(f"✅ PR作成完了: {pr_url}")
        return pr_url
    else:
        print(f"❌ PR作成エラー: {result.stderr}")
        return None
```

### 既存PR更新

```python
def update_pull_request(pr_number, pr_title, pr_body, current_branch, options):
    """既存のPRを更新"""

    print(f"📝 PR #{pr_number} を更新中...")

    # 1. リモートへプッシュ
    print(f"📤 {current_branch} をプッシュ中...")
    push_result = subprocess.run(
        ["git", "push", "origin", current_branch],
        capture_output=True,
        text=True
    )

    if push_result.returncode != 0:
        print(f"❌ プッシュ失敗: {push_result.stderr}")
        return None

    # 2. PRのタイトル・本文を更新
    update_command = f"""gh pr edit {pr_number} --title "{pr_title}" --body "$(cat <<'EOF'
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
        # PR URLを取得
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
        print(f"❌ PR更新エラー: {result.stderr}")
        return None
```

### ブランチ名生成

```python
def generate_branch_name(commit_groups):
    """コミットグループからブランチ名を生成"""

    # 主要な変更タイプを取得
    primary_type = commit_groups[0]['type'] if commit_groups else 'feature'

    # ファイル名から特徴を抽出
    all_files = []
    for group in commit_groups:
        all_files.extend(group['files'])

    # 共通ディレクトリ名を取得
    common_dir = os.path.commonprefix([os.path.dirname(f) for f in all_files])
    feature_name = os.path.basename(common_dir) if common_dir else 'update'

    # ブランチ名形式: {type}/{feature}-{timestamp}
    timestamp = datetime.now().strftime('%Y%m%d')
    branch_name = f"{primary_type}/{feature_name}-{timestamp}"

    # Git safe文字列に変換
    branch_name = re.sub(r'[^a-zA-Z0-9/_-]', '-', branch_name)

    return branch_name
```

## エラーハンドリング

### フォーマット失敗時

```python
if not execute_formatting(formatter_command, options):
    print("\n❌ フォーマット実行に失敗しました")
    print("\n💡 対処方法:")
    print("   1. エラーメッセージを確認")
    print("   2. 手動でフォーマットを実行")
    print("   3. --no-format でスキップ")

    if prompt_yes_no("フォーマットをスキップして続行しますか？"):
        options['no_format'] = True
    else:
        return None
```

### プッシュ失敗時

```python
if push_result.returncode != 0:
    print("\n❌ リモートへのプッシュに失敗しました")
    print(f"エラー: {push_result.stderr}")

    print("\n💡 考えられる原因:")
    print("   - リモートリポジトリが存在しない")
    print("   - 認証情報が無効")
    print("   - ネットワーク接続の問題")
    print("   - ブランチ保護ルールに違反")

    print("\n対処方法:")
    print("   1. git remote -v でリモートURL確認")
    print("   2. git push origin {branch} を手動実行")
    print("   3. GitHub認証を再設定")

    return None
```

### PR作成失敗時

```python
if result.returncode != 0:
    print("\n❌ PR作成に失敗しました")
    print(f"エラー: {result.stderr}")

    print("\n💡 考えられる原因:")
    print("   - gh CLI が未認証")
    print("   - リポジトリへのアクセス権限がない")
    print("   - 既存のPRと競合")

    print("\n対処方法:")
    print("   1. gh auth login で認証")
    print("   2. gh auth status で状態確認")
    print("   3. 手動でPR作成: gh pr create")

    return None
```

## プロジェクトタイプ別の動作

### JavaScript/TypeScript

```bash
# 検出内容
- package.json 存在
- package manager: pnpm
- formatter: pnpm run format

# 実行コマンド
pnpm run format
git add .
git commit -m "style: apply code formatting"
git push -u origin feature/ui-components
gh pr create --title "..." --body "..."
```

### Go

```bash
# 検出内容
- go.mod 存在
- formatter: gofmt

# 実行コマンド
gofmt -w .
git add .
git commit -m "style: apply Go formatting"
git push -u origin feature/api-handlers
gh pr create --title "..." --body "..."
```

### Python

```bash
# 検出内容
- pyproject.toml 存在
- formatter: black

# 実行コマンド
black .
git add .
git commit -m "style: apply code formatting"
git push -u origin feature/data-processing
gh pr create --title "..." --body "..."
```

## 統合フロー完全例

```python
def execute_pr_workflow(options):
    """PR作成ワークフローを実行"""

    print("🚀 PR作成ワークフロー開始\n")

    # Phase 1: フォーマッター検出
    print("📋 Phase 1: フォーマッター検出")
    formatter_command = detect_project_formatter()

    # Phase 2: フォーマット実行
    print("\n📋 Phase 2: フォーマット実行")
    if not execute_formatting(formatter_command, options):
        return None

    # Phase 3: コミット分割
    print("\n📋 Phase 3: インテリジェントコミット分割")
    commit_groups = create_intelligent_commits(options)
    print(f"✅ {len(commit_groups)} コミット作成完了")

    # Phase 3.5: 既存PR検出
    print("\n📋 Phase 3.5: 既存PR検出")
    action, existing_pr, current_branch = handle_existing_pr_workflow(
        commit_groups, options
    )

    # Phase 4: PR作成または更新
    print(f"\n📋 Phase 4: PR{action}")
    if action == 'create':
        pr_url = create_new_pull_request(commit_groups, current_branch, options)
    elif action == 'update':
        pr_title = generate_pr_title(commit_groups, options)
        pr_body = generate_pr_body_with_template(commit_groups, current_branch, options)
        pr_url = update_pull_request(
            existing_pr['number'], pr_title, pr_body, current_branch, options
        )
    else:
        print("❌ 処理を中止しました")
        return None

    if pr_url:
        print(f"\n✅ ワークフロー完了: {pr_url}")
    else:
        print("\n❌ ワークフロー失敗")

    return pr_url
```
