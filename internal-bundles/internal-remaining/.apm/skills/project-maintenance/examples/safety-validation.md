# セーフティ検証 - セーフティチェック実行例

実際のセーフティチェック実行例とトラブルシューティング。

## 基本的なセーフティチェック実行

### 正常ケース

```bash
$ /project-maintenance full

🔒 Safety Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✓ Git repository: Clean
✓ Current branch: feature/cleanup
✓ Uncommitted changes: None
✓ Checkpoint created: e5f6g7h
✓ Archive created: .cleanup_archive_20260212_150123.tar.gz
✓ Snapshot saved: .cleanup_snapshot_20260212_150123/

Proceeding with cleanup...
```

### 未コミット変更あり

```bash
$ /project-maintenance full

🔒 Safety Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  Git repository: Uncommitted changes detected

Modified files:
  M src/components/Button.tsx
  M src/utils/helpers.ts
  ?? temp/debug.log

Options:
1. Commit changes and create checkpoint
2. Stash changes temporarily
3. Abort cleanup

Choice (1/2/3): 1

✓ Changes committed
✓ Checkpoint created: f6g7h8i
✓ Proceeding with cleanup...
```

### mainブランチでの実行

```bash
$ /project-maintenance full

🔒 Safety Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  Current branch: main

You are about to run cleanup on the main branch.
This is not recommended for large changes.

Recommended actions:
1. Create a feature branch (cleanup/maintenance)
2. Continue on main branch (not recommended)
3. Abort

Choice (1/2/3): 1

✓ Created branch: cleanup/maintenance
✓ Switched to cleanup/maintenance
✓ Checkpoint created: g7h8i9j
✓ Proceeding with cleanup...
```

## 参照チェック実行例

### 安全な削除

```bash
🔍 Reference Checking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking: calculateOldMetric (src/utils/metrics.ts)

References found:
✓ Definition only (src/utils/metrics.ts:45)

Analysis:
- Not exported
- No external references
- No test references
- Safe to remove

Action: Will remove
```

### 参照が存在する場合

```bash
🔍 Reference Checking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking: formatDate (src/utils/formatters.ts)

References found:
1. Definition (src/utils/formatters.ts:12)
2. Usage (src/components/DateDisplay.tsx:23)
3. Test (tests/formatters.test.ts:45)

Analysis:
- 2 external references
- Used in components
- Has test coverage
- NOT safe to remove

Action: Will skip
```

### パブリックAPI保護

```bash
🔍 Reference Checking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking: exportedFunction (src/index.ts)

References found:
1. Definition (src/index.ts:10)
2. Export statement (src/index.ts:50)

Analysis:
- Exported in main index
- Public API
- Potentially used by consumers
- PROTECTED

Action: Will skip (Public API)
```

## テスト実行検証

### 成功ケース

```bash
✅ Post-Validation: Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running test suite...

Jest Test Results:
  Test Suites: 45 passed, 45 total
  Tests:       892 passed, 892 total
  Snapshots:   23 passed, 23 total
  Time:        12.456 s

✓ All tests passed
```

### 失敗ケース

```bash
❌ Post-Validation: Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running test suite...

Jest Test Results:
  Test Suites: 2 failed, 43 passed, 45 total
  Tests:       5 failed, 887 passed, 892 total

Failed Tests:
  ● src/utils/helpers.test.ts
    ○ calculateMetrics › should return correct value
      TypeError: calculateOldMetric is not a function

  ● src/components/Dashboard.test.tsx
    ○ Dashboard › should render metrics
      Error: Cannot find module 'utils/metrics'

⚠️  Tests failed after cleanup!

Analysis:
- calculateOldMetric was removed but still referenced
- Import path broken in Dashboard component

Actions:
1. Rollback to checkpoint g7h8i9j
2. Review failures and fix manually
3. Ignore failures (not recommended)

Choice (1/2/3): 1

🔄 Rolling back...
✓ Reset to checkpoint g7h8i9j
✓ Cleanup reverted

Please review the failures and retry with adjusted settings.
```

## リント/タイプチェック検証

### TypeScript型チェック成功

```bash
✅ Post-Validation: TypeScript
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running type check...

$ tsc --noEmit

✓ No type errors found
✓ Files checked: 456
✓ Time: 3.2s
```

### TypeScript型エラー

```bash
❌ Post-Validation: TypeScript
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running type check...

$ tsc --noEmit

Errors found:

src/components/Dashboard.tsx(23,10): error TS2304:
  Cannot find name 'calculateOldMetric'.

src/utils/formatters.ts(45,15): error TS2339:
  Property 'oldFormat' does not exist on type 'DateUtils'.

Found 2 errors.

⚠️  Type check failed after cleanup!

Actions:
1. Rollback to checkpoint g7h8i9j
2. Review errors and fix manually
3. Continue anyway (not recommended)

Choice (1/2/3): 2

Continuing without rollback.
Please fix the type errors before committing.

Error log saved: .cleanup_errors.log
```

### ESLint検証

```bash
✅ Post-Validation: ESLint
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running linter...

$ eslint . --ext .ts,.tsx

✓ No violations found
✓ Files checked: 456
✓ Time: 2.1s
```

## ビルド検証

### 成功ケース

```bash
✅ Post-Validation: Build
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running build...

$ npm run build

vite v5.0.0 building for production...
✓ 523 modules transformed.
✓ built in 2.34s

dist/assets/index-a1b2c3d4.js   456.78 kB │ gzip: 123.45 kB
dist/assets/index-e5f6g7h8.css   45.67 kB │ gzip: 12.34 kB

✓ Build successful
✓ Output size: 502.45 kB (reduced from 568.91 kB)
✓ Reduction: 11.7%
```

### ビルド失敗

```bash
❌ Post-Validation: Build
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running build...

$ npm run build

vite v5.0.0 building for production...

Error: Failed to resolve import "./utils/metrics" from
"src/components/Dashboard.tsx"

Build failed.

⚠️  Build failed after cleanup!

Actions:
1. Rollback to checkpoint g7h8i9j
2. Review errors and fix manually
3. Abort

Choice (1/2/3): 1

🔄 Rolling back...
✓ Reset to checkpoint g7h8i9j
✓ Build error resolved
```

## 保護ファイルチェック

### 保護ファイル検出

```bash
🛡️  Protected Files Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Scanning cleanup targets...

Protected files detected:
  .env (environment variables)
  .claude/commands/task.md (Claude command)
  config/database.yml (configuration)
  .git/config (git configuration)

✓ Protected files will be skipped
✓ 12 files protected
```

### アクティブファイルチェック

```bash
⚠️  Active Files Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking for active processes...

Active files detected:
  logs/app.log (PID 12345: node server.js)
  temp/session.tmp (PID 67890: npm run dev)

Options:
1. Skip active files
2. Stop processes and continue
3. Abort cleanup

Choice (1/2/3): 1

✓ Active files will be skipped
✓ 2 files skipped
```

## バックアップ検証

### バックアップ作成確認

```bash
💾 Backup Creation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Creating backups...

✓ Git checkpoint: h8i9j0k
  Branch: cleanup/maintenance
  Files staged: 23
  Commit message: "Pre-cleanup checkpoint: 2026-02-12 15:30:45"

✓ File archive: .cleanup_archive_20260212_153045.tar.gz
  Files archived: 45
  Archive size: 89.5 MB
  Compression: gzip

✓ Snapshot: .cleanup_snapshot_20260212_153045/
  Files tracked: 1,234
  Metadata saved: snapshot.json

All backups created successfully.
```

### バックアップ整合性確認

```bash
🔍 Backup Verification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Verifying backups...

Git Checkpoint:
  ✓ Commit exists: h8i9j0k
  ✓ Branch valid: cleanup/maintenance
  ✓ Clean working tree

File Archive:
  ✓ Archive exists: .cleanup_archive_20260212_153045.tar.gz
  ✓ Archive readable
  ✓ 45 files archived
  ✓ No corruption detected

Snapshot:
  ✓ Snapshot directory exists
  ✓ Metadata valid
  ✓ File hashes match

All backups verified successfully.
```

## 段階的検証ワークフロー

### Phase-by-Phase検証

```bash
📊 Staged Validation Workflow
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phase 1: Pre-validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Git status check
✓ Branch validation
✓ Backup creation
✓ Snapshot creation

Phase 2: Code Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Symbol detection
✓ Reference checking
✓ Public API protection
✓ Test reference verification

Phase 3: Cleanup Execution
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Unused code removal
✓ Debug statement removal
✓ File cleanup
✓ Documentation consolidation

Phase 4: Immediate Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Running tests...
✓ Unit tests passed
✓ Integration tests passed

Phase 5: Quality Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ TypeScript type check
✓ ESLint validation
✓ Prettier formatting

Phase 6: Build Verification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Production build
✓ Bundle size check
✓ Asset optimization

All phases completed successfully!
```

## トラブルシューティング例

### ケース1: 誤って重要なコードを削除

```bash
❌ Error: Important code removed

Symptom:
  Tests failing: "Cannot find function calculateMetrics"

Analysis:
  - calculateMetrics was marked as unused
  - Actually used via dynamic import
  - Not detected by static analysis

Solution:
  1. Rollback to checkpoint
  2. Add @preserve comment
  3. Retry cleanup

$ git reset --hard h8i9j0k

# Add @preserve comment
# @preserve: Used via dynamic import
export function calculateMetrics() { ... }

$ /project-maintenance full
```

### ケース2: テストファイルが削除された

```bash
❌ Error: Test file missing

Symptom:
  Test suite reduced from 45 to 43

Analysis:
  - Old test files detected as unused
  - Actually contain important test cases
  - Pattern matching too aggressive

Solution:
  1. Restore from archive
  2. Update .cleanupignore
  3. Retry

$ tar -xzf .cleanup_archive_20260212_153045.tar.gz tests/old/

# Add to .cleanupignore
tests/**/*_old.test.ts

$ /project-maintenance full
```

### ケース3: 設定ファイルが破損

```bash
❌ Error: Configuration corrupted

Symptom:
  Build fails with "Invalid configuration"

Analysis:
  - Comments in config file removed
  - Comments contained important info
  - Config parser failed

Solution:
  1. Rollback specific file
  2. Protect config files
  3. Manual review

$ git checkout h8i9j0k -- config/app.config.ts

# Add to .cleanupignore
config/**

$ /project-maintenance full --code-only
```

## ベストプラクティス

### 検証チェックリスト

```markdown
## Pre-Cleanup Checklist

- [ ] Git status is clean
- [ ] On feature branch (not main)
- [ ] All tests passing
- [ ] No pending changes
- [ ] Backup created

## During Cleanup

- [ ] Monitor progress
- [ ] Review warnings
- [ ] Note protected files
- [ ] Track skipped items

## Post-Cleanup Checklist

- [ ] All tests passing
- [ ] No type errors
- [ ] No lint violations
- [ ] Build successful
- [ ] Manual testing done
- [ ] Documentation updated
```

### 段階的検証アプローチ

1. Small scope first: 小規模から開始
2. Frequent testing: 頻繁にテスト実行
3. Incremental commits: 段階的にコミット
4. Team review: チームレビューを依頼
5. Monitoring: 本番環境での監視

### 安全な実行パターン

```bash
# Pattern 1: Conservative (最も安全)
/project-maintenance files --dry-run
# review
/project-maintenance files
# test
git commit -m "cleanup: remove temporary files"

# Pattern 2: Balanced
/project-maintenance full --code-only --dry-run
# review
/project-maintenance full --code-only
# test
git commit -m "cleanup: remove unused code"

# Pattern 3: Aggressive (慎重に)
/project-maintenance full --dry-run
# extensive review
/project-maintenance full
# comprehensive testing
git commit -m "cleanup: full project cleanup"
```
