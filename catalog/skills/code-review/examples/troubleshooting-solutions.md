# トラブルシューティング

code-review のよくある問題と解決方法です。

## レビュー対象関連

### レビュー対象が想定と違う

### 症状

- `--simple` や `--detailed` を実行したが、見てほしい差分が対象に入っていない

### 原因

- target flag を付けずに実行した
- staged / recent / branch diff の優先順を想定と取り違えた

### 解決方法

- 対象を明示する
  - `--staged`: ステージ済み差分だけを見る
  - `--recent`: 直前コミットとの差分を見る
  - `--branch <name>`: 指定ブランチとの差分を見る
- フラグ未指定時は fallback order に従うため、意図が明確なら必ず target flag を付ける
- dirty worktree はそのままレビュー可能であり、レビューのための commit や reset は不要

## Serena オプション関連

### Serena オプションが動作しない

### 症状

```text
semantic analysis unavailable
impact analysis skipped
```

### 原因

- semantic tooling が未導入
- 現在の実行環境で利用できない

### 解決方法

- optional 機能として扱い、通常の detailed review を継続する
- impact 分析が必要な理由が強い場合だけ、利用可能な semantic tooling を別途整備する
- 対象ファイルを絞って再実行する

## プロジェクト判定関連

### プロジェクトタイプが誤検出される

### 症状

- 想定と違うプロジェクト種別で評価される

### 原因

- `package.json`, `go.mod`, `tsconfig.json` などのシグナルが弱い
- モノレポや特殊構成で default rule が外れる

### 暫定的な解決方法

- `./.claude/review-guidelines.md` などの project guideline で明示的に前提を書く
- `config/default-projects.json` の判定基準と差分があるか確認する

## スタック別観点が十分に反映されない

### 症状

- TypeScript や React の観点が薄い
- security や clean architecture の観点が不足する

### 原因

- 参照可能な stack-specific skill が無い
- project guideline が不足している

### 解決方法

- 利用可能な skill があれば読む
- 無い場合でも review lens 自体は落とさず、`references/tech-stack-skills.md` を根拠に観点を補う
- プロジェクト固有ルールがあるなら guideline file に追記する
