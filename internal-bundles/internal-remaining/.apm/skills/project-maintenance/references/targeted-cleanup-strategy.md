# ターゲットクリーンアップ戦略 - ファイル単位クリーンアップ

特定のファイルやパターンに対する効率的なクリーンアップ戦略。開発アーティファクトを削除しながら、動作中のコードを保持します。

## 概要

開発プロセスで生成される一時ファイル、ログファイル、デバッグファイル等を安全に削除し、プロジェクトを整理します。全体解析は行わず、特定のパターンに焦点を当てることで、高速かつ軽量な実行を実現します。

## クリーンアップ対象

### 1. 一時ファイル

```bash
**/*.log          # ログファイル
**/*.tmp          # 一時ファイル
**/*~             # エディタバックアップ
**/*.swp          # Vimスワップファイル
**/*.bak          # バックアップファイル
```

### 2. システムファイル

```bash
**/.DS_Store      # macOS
**/Thumbs.db      # Windows
**/desktop.ini    # Windows
```

### 3. コンパイル生成物

```bash
**/*.pyc          # Pythonバイトコード
**/__pycache__    # Pythonキャッシュ
**/*.class        # Javaクラスファイル
**/*.o            # Cオブジェクトファイル
**/*.obj          # C++オブジェクトファイル
```

### 4. キャッシュディレクトリ

```bash
node_modules/.cache
.next/cache
.turbo
.eslintcache
.pytest_cache
```

## 実行戦略

### Phase 1: セーフティチェック

```bash
# 安全なチェックポイント作成
git add -A
git commit -m "Pre-cleanup checkpoint" || echo "No changes to commit"

# Gitステータス確認
git status

# 未コミット変更の警告
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: Uncommitted changes detected"
    read -p "Continue? (y/n) " -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
```

### チェック内容

1. Gitチェックポイント作成（ロールバック用）
2. 未コミット変更の確認
3. ユーザー確認プロンプト

### Phase 2: パターンマッチングによるファイル検出

ネイティブツールを使用した効率的なファイル検出:

```python
def detect_cleanup_targets(pattern=None):
    """クリーンアップ対象ファイルを検出"""

    # デフォルトパターン
    default_patterns = [
        "**/*.log",
        "**/*.tmp",
        "**/*~",
        "**/.DS_Store",
        "**/Thumbs.db",
        "**/*.pyc",
        "**/__pycache__"
    ]

    # パターンが指定された場合はそれを使用
    patterns = [pattern] if pattern else default_patterns

    # Globツールでファイル検出
    files_to_clean = []
    for p in patterns:
        matches = glob(p)
        files_to_clean.extend(matches)

    return files_to_clean
```

### ツール選択

- Glob: ファイルパターンマッチング（高速、効率的）
- Grep: デバッグステートメント検出
- Read: ファイル内容確認（削除前検証）

### Phase 3: 保護機能

重要なファイル・ディレクトリを自動的に保護:

```python
def is_protected_file(file_path):
    """重要ファイルの保護"""

    # 必須ディレクトリ
    protected_dirs = [
        ".claude/",        # Claudeコマンド・設定
        ".git/",           # バージョン管理
        "node_modules/",   # 依存関係
        "vendor/",         # 依存関係（PHP等）
        ".venv/",          # Python仮想環境
        "venv/"            # Python仮想環境
    ]

    # 必須設定ファイル
    protected_files = [
        ".env",
        ".env.local",
        "config.yml",
        "config.yaml",
        "secrets.json"
    ]

    # ディレクトリチェック
    for protected_dir in protected_dirs:
        if protected_dir in file_path:
            return True

    # ファイル名チェック
    file_name = os.path.basename(file_path)
    if file_name in protected_files:
        return True

    return False
```

### 保護対象

1. 設定ディレクトリ: `.claude/`, `.git/`
2. 依存関係: `node_modules/`, `vendor/`
3. 環境変数: `.env*`
4. 設定ファイル: `config.*`, `secrets.*`

### Phase 4: アクティブプロセスチェック

削除前にアクティブプロセスを確認:

```python
def check_active_processes(file_path):
    """ファイルが使用中かチェック"""

    # lsof (List Open Files) でチェック
    result = subprocess.run(
        ["lsof", file_path],
        capture_output=True,
        text=True
    )

    # プロセスが見つかった場合
    if result.returncode == 0:
        processes = result.stdout.strip()
        return True, processes

    return False, None
```

### チェック内容

- ファイルをオープンしているプロセス
- 実行中のプログラムによる参照
- ネットワークソケット（ログファイル等）

### Phase 5: 段階的削除

安全な削除実行:

```python
def safe_remove(file_path):
    """安全なファイル削除"""

    # 保護ファイルチェック
    if is_protected_file(file_path):
        print(f"Protected: {file_path}")
        return False

    # アクティブプロセスチェック
    is_active, processes = check_active_processes(file_path)
    if is_active:
        print(f"Active: {file_path}")
        print(f"Processes: {processes}")
        return False

    # ファイルサイズ確認（大きいファイルは警告）
    size = os.path.getsize(file_path)
    if size > 100 * 1024 * 1024:  # 100MB
        print(f"Large file: {file_path} ({size / 1024 / 1024:.2f}MB)")
        confirm = input("Delete? (y/n): ")
        if confirm.lower() != 'y':
            return False

    # 削除実行
    try:
        if os.path.isdir(file_path):
            shutil.rmtree(file_path)
        else:
            os.remove(file_path)
        return True
    except Exception as e:
        print(f"Error removing {file_path}: {e}")
        return False
```

### 削除フロー

1. 保護ファイルチェック → スキップ
2. アクティブプロセスチェック → スキップ
3. ファイルサイズ確認 → 大きい場合は確認
4. 削除実行 → エラーハンドリング

## 使用例

### 基本的な使用

```bash
# デフォルトパターンでクリーンアップ
/project-maintenance files

# 特定パターンでクリーンアップ
/project-maintenance files "**/*.log"

# 複数パターン
/project-maintenance files "**/*.{log,tmp}"
```

### プレビューモード

```bash
# 削除対象をプレビューのみ
/project-maintenance files --dry-run

# 詳細情報付きプレビュー
/project-maintenance files --dry-run --verbose
```

### カスタムパターン

```bash
# プロジェクト固有の一時ファイル
/project-maintenance files "**/generated/*.tmp"

# 古いバックアップファイル
/project-maintenance files "**/*.backup"

# 特定ディレクトリのみ
/project-maintenance files "src/**/*.log"
```

## 実行レポート

削除後、詳細なレポートを提供:

```markdown
🧹 **File Cleanup Report**
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📋 Summary

- Files scanned: 1,234
- Files deleted: 45
- Space freed: 156.8 MB
- Protected files: 12
- Active files skipped: 3

## 📁 Deleted by Type

- Log files: 23 (89.5 MB)
- Temporary files: 15 (45.2 MB)
- Cache files: 5 (18.3 MB)
- System files: 2 (3.8 MB)

## 🛡️ Protected Files

- .env (environment variables)
- config/database.yml (configuration)
- .claude/commands/task.md (Claude command)

## ⚠️ Skipped Files

- logs/app.log (in use by PID 12345)
- tmp/session.tmp (in use by PID 67890)
- cache/build.cache (in use by PID 24680)

## 🔄 Next Steps

- Review active processes if needed
- Consider adding patterns to .cleanupignore
- Run tests to ensure nothing broke
```

## ファイル年齢による判定

古いファイルを優先的に削除:

```python
def filter_by_age(files, max_age_days=7):
    """ファイル年齢でフィルタリング"""

    current_time = time.time()
    max_age_seconds = max_age_days * 24 * 60 * 60

    old_files = []
    for file_path in files:
        # 最終更新時刻を取得
        mtime = os.path.getmtime(file_path)
        age_seconds = current_time - mtime

        # 指定日数以上古い場合
        if age_seconds > max_age_seconds:
            old_files.append(file_path)

    return old_files
```

### 使用例

```bash
# 7日以上古いログファイルのみ削除
/project-maintenance files "**/*.log" --older-than 7

# 30日以上古い一時ファイルのみ削除
/project-maintenance files "**/*.tmp" --older-than 30
```

## バッチ処理

類似ファイルをバッチで処理:

```python
def batch_process(files):
    """類似ファイルをグループ化してバッチ処理"""

    # 拡張子でグループ化
    groups = {}
    for file_path in files:
        ext = os.path.splitext(file_path)[1]
        if ext not in groups:
            groups[ext] = []
        groups[ext].append(file_path)

    # グループごとに確認
    for ext, group_files in groups.items():
        print(f"\nFound {len(group_files)} {ext} files")
        print(f"Total size: {sum(os.path.getsize(f) for f in group_files) / 1024 / 1024:.2f} MB")

        confirm = input(f"Delete all {ext} files? (y/n/s for selective): ")
        if confirm.lower() == 'y':
            for file_path in group_files:
                safe_remove(file_path)
        elif confirm.lower() == 's':
            for file_path in group_files:
                print(f"\n{file_path}")
                confirm_single = input("Delete? (y/n): ")
                if confirm_single.lower() == 'y':
                    safe_remove(file_path)
```

## .cleanupignore ファイル

除外パターンを定義:

```gitignore
# 保持する一時ファイル
temp/important/*.tmp

# 保持するログファイル
logs/audit/*.log

# 保持するキャッシュ
.cache/critical/

# 特定の拡張子を除外
*.backup
```

### 読み込みロジック

```python
def load_ignore_patterns():
    """`.cleanupignore` から除外パターンを読み込み"""

    ignore_file = ".cleanupignore"
    if not os.path.exists(ignore_file):
        return []

    with open(ignore_file, 'r') as f:
        patterns = []
        for line in f:
            line = line.strip()
            # コメントと空行をスキップ
            if line and not line.startswith('#'):
                patterns.append(line)

    return patterns

def should_ignore(file_path, ignore_patterns):
    """除外パターンに一致するかチェック"""
    return any(fnmatch.fnmatch(file_path, pattern) for pattern in ignore_patterns)
```

## Git統合

Git追跡ファイルの保護:

```python
def is_git_tracked(file_path):
    """Gitで追跡されているかチェック"""

    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", file_path],
        capture_output=True,
        stderr=subprocess.DEVNULL
    )

    return result.returncode == 0

def filter_untracked_only(files):
    """未追跡ファイルのみをフィルタ"""

    untracked = []
    for file_path in files:
        if not is_git_tracked(file_path):
            untracked.append(file_path)

    return untracked
```

### 使用例

```bash
# 未追跡ファイルのみ削除
/project-maintenance files --untracked-only
```

## ベストプラクティス

### 実行前

1. Gitコミット: 重要な変更をコミット
2. dry-run確認: `--dry-run` でプレビュー
3. パターン限定: 広すぎるパターンは避ける

### 実行中

1. 段階的実行: 小さいパターンから開始
2. 確認プロンプト: 大きいファイルは確認
3. ログ保持: 削除ログを記録

### 実行後

1. 動作確認: 基本機能の動作確認
2. テスト実行: 自動テストの実行
3. ロールバック準備: 問題があればすぐ復旧

## トラブルシューティング

### 問題: 重要なファイルが削除された

### 原因

### 対処

```bash
# ロールバック
git reset --hard HEAD~1

# より限定的なパターンで再実行
/project-maintenance files "logs/debug/*.log"
```

### 問題: アクティブファイルが削除できない

### 原因

### 対処

```bash
# プロセスを確認
lsof <file_path>

# プロセスを停止してから再実行
kill <PID>
/project-maintenance files
```

### 問題: 削除後にビルドが失敗

### 原因

### 対処

```bash
# キャッシュを再生成
npm run build  # or equivalent

# 次回から除外
echo ".cache/critical/" >> .cleanupignore
```

## パフォーマンス最適化

### 並列処理

```python
from concurrent.futures import ThreadPoolExecutor

def parallel_cleanup(files, max_workers=4):
    """並列でファイルを削除"""

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        results = executor.map(safe_remove, files)

    return list(results)
```

### キャッシング

```python
# 保護ファイルチェックのキャッシング
_protected_cache = {}

def is_protected_file_cached(file_path):
    """キャッシュ付き保護チェック"""

    if file_path not in _protected_cache:
        _protected_cache[file_path] = is_protected_file(file_path)

    return _protected_cache[file_path]
```
