# PR Comment Integration — レビュー後コメント対処

レビュー完了後、`gh-address-comments` スキルへ処理を委譲する。

## フロー

### Step 1: PR 検出

`gh pr view --json number,url,title,state` で現在ブランチの PR を検出。
PR がない場合 → サイレントスキップ。

### Step 2: gh 認証確認

`gh auth status` を確認。
認証されていない場合 → サイレントスキップ（エラーにしない）。

### Step 3: gh-address-comments スキルへ委譲

`gh-address-comments` スキルを呼び出し、コメント取得・対処をすべて委譲。
コメント対処の詳細（番号付きリスト提示、ユーザー選択、修正適用）は当該スキルの定義に従う。

## スキップ条件

- `--no-comments` フラグが指定された場合
- 現在ブランチに PR が存在しない場合
- `gh auth status` が失敗する場合（認証なし環境、CI 環境）
- 未対応コメントが 0 件の場合（gh-address-comments 側で処理）

上記いずれの場合もサイレントスキップ（エラーにしない）。

## 実行タイミング

- 必ずメインのコードレビュー完了後に実行する
- コメント対処はレビュー本体の補助フローであり、前提として git 操作や checkpoint を要求しない
- コメント対処が不要または不可能な場合でも、レビュー本体は成功として扱う

## 依存スキル

- `gh-address-comments` — コメント取得・番号付き提示・ユーザー選択・修正適用の全責務
  - flake input 経由でスキルとして配布（`~/.claude/skills/gh-address-comments/`）
