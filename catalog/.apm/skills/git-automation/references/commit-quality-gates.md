# Commit Quality Gates - 品質ゲート実行ルール

コミット前に実行される品質チェックの詳細仕様です。

## 品質ゲートの目的

- 不適切なコードのコミット防止
- ビルド破壊の未然防止
- テスト失敗の早期発見
- コード規約の自動適用

## 実行順序

```
1. Lint (静的解析)
   ↓ 成功
2. Test (自動テスト)
   ↓ 成功
3. Build (ビルド検証)
   ↓ 成功
4. Commit作成
```

各ステップが失敗した場合、後続の処理は実行されません。

## プロジェクト自動検出

project-detector共通ユーティリティを使用してプロジェクトタイプを判定します：

```python
from shared.project_detector import detect_project_type, detect_formatter

def detect_quality_commands():
    """プロジェクトの品質チェックコマンドを検出"""
    project = detect_project_type()

    commands = {
        'lint': None,
        'test': None,
        'build': None
    }

    if 'node' in project['stack']:
        # JavaScript/TypeScript
        if project.get('package_manager') == 'pnpm':
            commands['lint'] = 'pnpm run lint'
            commands['test'] = 'pnpm test'
            commands['build'] = 'pnpm run build'
        elif project.get('package_manager') == 'yarn':
            commands['lint'] = 'yarn lint'
            commands['test'] = 'yarn test'
            commands['build'] = 'yarn build'
        else:
            commands['lint'] = 'npm run lint'
            commands['test'] = 'npm test'
            commands['build'] = 'npm run build'

    elif 'go' in project['stack']:
        # Go
        commands['lint'] = 'go vet ./...'
        commands['test'] = 'go test ./...'
        commands['build'] = 'go build ./...'

    elif 'python' in project['stack']:
        # Python
        commands['lint'] = 'ruff check .'
        commands['test'] = 'pytest'
        commands['build'] = None  # Pythonはビルド不要

    elif 'rust' in project['stack']:
        # Rust
        commands['lint'] = 'cargo clippy'
        commands['test'] = 'cargo test'
        commands['build'] = 'cargo build'

    return commands
```

## Lint (静的解析)

### 目的

- コード規約違反の検出
- 潜在的なバグの発見
- スタイル問題の指摘

### JavaScript/TypeScript

```bash
# ESLint
npm run lint
pnpm run lint
yarn lint

# 自動修正付き
npm run lint -- --fix
pnpm run lint --fix
yarn lint --fix
```

### Go

```bash
# go vet
go vet ./...

# golangci-lint（推奨）
golangci-lint run

# gofmt チェック
gofmt -l .
```

### Python

```bash
# ruff（推奨）
ruff check .

# ruff 自動修正
ruff check . --fix

# black
black --check .

# flake8
flake8 .
```

### Rust

```bash
# clippy
cargo clippy

# clippy 厳格モード
cargo clippy -- -D warnings
```

### スキップ条件

- `lint` コマンドが package.json/Makefile 等に存在しない
- `--skip-lint` オプション使用時
- `--no-verify` オプション使用時

### エラーハンドリング

```python
def run_lint():
    """Lintを実行"""
    lint_command = detect_quality_commands()['lint']

    if not lint_command:
        print("⏩ Lint: コマンド未検出（スキップ）")
        return True

    print(f"🔍 Lint実行: {lint_command}")
    result = subprocess.run(
        lint_command.split(),
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✅ Lint: 成功")
        return True
    else:
        print(f"❌ Lint: 失敗")
        print(result.stdout)
        print(result.stderr)
        print("\n💡 修正方法:")
        print(f"   1. {lint_command} --fix を実行")
        print(f"   2. 手動で修正")
        print(f"   3. --skip-lint でスキップ")
        return False
```

## Test (自動テスト)

### 目的

- 既存機能の動作保証
- リグレッション防止
- 変更の影響範囲確認

### JavaScript/TypeScript

```bash
# Jest
npm test
pnpm test
yarn test

# Vitest
npm run test
pnpm test
yarn test

# 特定ファイルのみ
npm test -- path/to/test
```

### Go

```bash
# すべてのテスト
go test ./...

# カバレッジ付き
go test -cover ./...

# 詳細出力
go test -v ./...
```

### Python

```bash
# pytest
pytest

# カバレッジ付き
pytest --cov

# 特定ファイル
pytest tests/test_example.py
```

### Rust

```bash
# すべてのテスト
cargo test

# 詳細出力
cargo test -- --nocapture
```

### スキップ条件

- `test` コマンドが存在しない
- テストファイルが存在しない
- `--skip-tests` オプション使用時
- `--no-verify` オプション使用時

### エラーハンドリング

```python
def run_tests():
    """テストを実行"""
    test_command = detect_quality_commands()['test']

    if not test_command:
        print("⏩ Test: コマンド未検出（スキップ）")
        return True

    print(f"🧪 Test実行: {test_command}")
    result = subprocess.run(
        test_command.split(),
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✅ Test: 成功")
        return True
    else:
        print(f"❌ Test: 失敗")
        print(result.stdout)
        print(result.stderr)
        print("\n💡 対処方法:")
        print(f"   1. 失敗したテストを修正")
        print(f"   2. --skip-tests でスキップ（推奨しない）")
        return False
```

## Build (ビルド検証)

### 目的

- ビルドエラーの事前検出
- 型エラーの確認（TypeScript等）
- 依存関係の検証

### JavaScript/TypeScript

```bash
# ビルド
npm run build
pnpm build
yarn build

# 型チェック（TypeScript）
npm run typecheck
tsc --noEmit
```

### Go

```bash
# ビルド
go build ./...

# クロスコンパイル
GOOS=linux GOARCH=amd64 go build
```

### Python

```bash
# Python はビルド不要
# 型チェックのみ実施
mypy .
pyright
```

### Rust

```bash
# ビルド
cargo build

# リリースビルド
cargo build --release
```

### スキップ条件

- `build` コマンドが存在しない
- Python等ビルド不要な言語
- `--skip-build` オプション使用時
- `--no-verify` オプション使用時

### エラーハンドリング

```python
def run_build():
    """ビルドを実行"""
    build_command = detect_quality_commands()['build']

    if not build_command:
        print("⏩ Build: コマンド未検出（スキップ）")
        return True

    print(f"🔨 Build実行: {build_command}")
    result = subprocess.run(
        build_command.split(),
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print("✅ Build: 成功")
        return True
    else:
        print(f"❌ Build: 失敗")
        print(result.stdout)
        print(result.stderr)
        print("\n💡 対処方法:")
        print(f"   1. ビルドエラーを修正")
        print(f"   2. 依存関係を確認")
        print(f"   3. --skip-build でスキップ（推奨しない）")
        return False
```

## 統合フロー

```python
def run_quality_gates(options):
    """品質ゲートを順次実行"""

    if options.get('no_verify'):
        print("⏩ すべての品質チェックをスキップします")
        return True

    # Lint
    if not options.get('skip_lint'):
        if not run_lint():
            return False
    else:
        print("⏩ Lint: スキップ（--skip-lint）")

    # Test
    if not options.get('skip_tests'):
        if not run_tests():
            return False
    else:
        print("⏩ Test: スキップ（--skip-tests）")

    # Build
    if not options.get('skip_build'):
        if not run_build():
            return False
    else:
        print("⏩ Build: スキップ（--skip-build）")

    print("\n✅ すべての品質チェックに成功しました")
    return True
```

## オプション一覧

| オプション     | 説明              | 影響範囲            |
| -------------- | ----------------- | ------------------- |
| `--no-verify`  | すべてスキップ    | Lint + Test + Build |
| `--skip-lint`  | Lintのみスキップ  | Lint                |
| `--skip-tests` | Testのみスキップ  | Test                |
| `--skip-build` | Buildのみスキップ | Build               |

## ベストプラクティス

### 開発中

```bash
# 最低限のチェック（時間短縮）
/git-automation commit --skip-tests

# Lint自動修正後にコミット
npm run lint -- --fix
/git-automation commit
```

### レビュー前

```bash
# 完全なチェック
/git-automation commit

# すべての品質ゲートを通過
```

### 緊急時

```bash
# すべてスキップ（例外的措置）
/git-automation commit --no-verify

# 理由: 本番障害の緊急修正等
```

## エラーリカバリー

### Lint失敗時

```bash
# 1. 自動修正を試す
npm run lint -- --fix
pnpm run lint --fix

# 2. 手動修正

# 3. 再度コミット
/git-automation commit
```

### Test失敗時

```bash
# 1. 失敗したテストを確認
npm test

# 2. テストを修正

# 3. 再度実行
/git-automation commit
```

### Build失敗時

```bash
# 1. エラー内容を確認
npm run build

# 2. 型エラー・依存関係を修正

# 3. 再度ビルド
npm run build

# 4. 成功したらコミット
/git-automation commit
```

## CI/CDとの連携

品質ゲートはCI/CDパイプラインと同じチェックを実行することで、プッシュ前に問題を検出できます：

```yaml
# .github/workflows/ci.yml の例
name: CI

on: [push, pull_request]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup
        run: npm install
      - name: Lint
        run: npm run lint
      - name: Test
        run: npm test
      - name: Build
        run: npm run build
```

ローカルでの品質ゲートとCI/CDを一致させることで、プッシュ前に失敗を検出できます。
