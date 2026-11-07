# catalog の APM 正規配置への移行プラン

- Issue: #68（根拠・PoC 結果・参考リンクは Issue 側が正本）
- 対象: `catalog/` のみ。`optional-skills/`、`manual-skills/`、`private-skills/`、外部依存と MCP の運用は変更しない
- 前提バージョン: APM CLI 0.35.0（現行 `apm.lock.yaml` の生成版）

## ゴール

`catalog` を `package_type: apm_package` として成立させ、素の consumer が `apm install jey3dayo/apm-workspace/catalog` だけで skills / instructions / agents を取得できる状態にする。自作 runtime sync（`scripts/apm-workspace.sh` / `.ps1`）は、APM が担えない部分（host-local MCP、Pi 向け sync、Claude 固有ルール等）だけに縮小する。

## 移行対応表

| 現在 | 移行先 | 備考 |
| --- | --- | --- |
| `catalog/skills/<id>/**`（34 件） | `catalog/.apm/skills/<id>/**` | `.apm/` が存在するとルート側 `skills/` は pack 時に無視されるため、二重配置にせず移動する |
| `catalog/AGENTS.md` | `catalog/.apm/instructions/*.instructions.md`（H2 節ごとに分割、下表） | `applyTo` なし = 無条件ルールとしてコンパイル済みコンテキストへ畳み込み。frontmatter に `description` 必須 |
| `catalog/agents/*.md`（10 件） | `catalog/.apm/agents/*.agent.md` | Claude / Cursor は verbatim。Codex は `.codex/agents/*.toml` が生成されるが `tools` / `color` / `disallowedTools` は落ちる（判断ポイント 2） |
| `catalog/rules/claude-md-design.md` | `catalog/.apm/instructions/claude-md-design.instructions.md` | フロントマターの `paths:` を `applyTo:` へ変換（PoC で変換確認済み） |
| `catalog/claude/rules/model-policy.md` | 当面は移行しない | Claude 固有ルール。判断ポイント 1 |
| `catalog/commands/`（空） | 何もしない | 将来 prompts を作る場合は `.apm/prompts/*.prompt.md` |
| `catalog/apm.yml` | `targets` を明記（claude / codex / cursor / agent-skills） | 現行は未指定 |
| `catalog/.apm/.gitkeep` | 削除 | 実 primitives が入るため不要になる |

### AGENTS.md の分割表（H2 節 → instruction）

| 節 | ファイル名 |
| --- | --- |
| 事実確認 | `fact-check.instructions.md` |
| Definition of Done (DoD) | `definition-of-done.instructions.md` |
| 停止・確認ポリシー | `stop-and-confirm.instructions.md` |
| 秘密情報・環境変数の安全 | `secrets-and-env.instructions.md` |
| 開発原則 | `development-principles.instructions.md` |
| モデル運用方針（Orchestrator-Worker） | `model-orchestration.instructions.md` |
| コマンド選択 | `command-selection.instructions.md` |
| ファイル操作原則 | `file-operations.instructions.md` |
| ドキュメント作成の優先順位 | `doc-placement.instructions.md` |
| MCP 配置方針 | `mcp-placement.instructions.md` |
| Git コミット規約 | `git-commit.instructions.md` |
| PR マージ方針 | `pr-merge.instructions.md` |
| issue / PR 本文の扱い | `issue-pr-body.instructions.md` |
| Git Worktree 方針 | `git-worktree.instructions.md` |
| コミュニケーション原則 | `communication.instructions.md` |
| 禁止事項 | `prohibitions.instructions.md` |

- H3 節（検証粒度、推奨ワークフロー、ブラウザ操作の選択）は親の H2 ファイル内に残す
- 本文中の相互参照（節名や `catalog/AGENTS.md` への言及）は、分割に合わせて instruction 名への参照に書き換える
- 分割後の各ファイルが単独で読めること（前提を他の節に置かない）をレビュー条件にする

## 判断ポイント

1. **model-policy の扱い**: Claude 固有のモデル運用ルールで、instructions 化すると全ターゲットのコンテキストに畳み込まれてノイズになる。当面はカスタム sync の残留対象として明記し、Phase 4 で再判断する（推奨）。
2. **Codex 向け agents のツール制限喪失**: APM は Codex の `.toml` に `tools` / `disallowedTools` を保持できない。現行は Codex に agents 自体が届いていないため純増ではあるが、`researcher` のように書込み禁止が効いている agent は、Codex で無制限になる。許容するか、該当 agent を Codex 対象から外す手段（targets の粒度）を Phase 1 で確認して決める。
3. **OpenCode の agents face**: 現行は形式不一致（`tools` の文字列形式、名前付き `color`）のため対象外。`.agent.md` 化しても OpenCode は `tools` の mapping 形式と hex カラーを要求するため、そのままでは開けられない。開けるかは Phase 1 の判断に含める（現行維持も可）。

## フェーズ計画

### Phase 0: 残りの検証

- user-scope（`apm install -g`）での挙動確認: グローバル instructions が `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` の user-scope root context としてどう生成されるか。現行 sync の配布物と diff を取り、意味差分がないことを確認する
- PoC で対象外だった target（opencode、pi 向け sync）への影響確認
- ゲート: user-scope の生成物が現行配布物と意味的に一致する見通しが立つこと。一致しない場合は instructions の畳み込み方（単一ファイル維持など）を再設計する

### Phase 1: agents の移行

- `catalog/agents/*.md` → `catalog/.apm/agents/*.agent.md` へ rename（本文・フロントマターは原則そのまま）
- `prepare:catalog` の staging と doctor の参照パスを新配置へ追随させる
- 判断ポイント 2 / 3 を決める
- ゲート: `mise run verify` 通過。Claude / Cursor の配布物が従来と同一であること。Codex に `.codex/agents/*.toml` が生成される場合は警告内容を記録すること

### Phase 2: instructions の移行

- AGENTS.md を分割表どおりに分割し、rules 2 件のうち `claude-md-design` を統合する
- `apm compile --validate` と compile 出力（user-scope / project-scope 両方）と現行配布物の diff 検品
- ゲート: compile 出力と現行の `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.md` の意味差分がゼロ、または差分が意図したものだけであること

### Phase 3: skills の `.apm` 化（本丸）

- `catalog/skills/` → `catalog/.apm/skills/` へ移動し、`package_type` が `apm_package` になることを lock で確認する
- `prepare:catalog` / `install:catalog` / repair 系タスクの前提パスを全て追随させる
- ゲート: 再生成した `apm.lock.yaml` の catalog の `deployed_files` が、従来の skills 310 件 + instructions 分 + agents 分を含み、欠落ゼロであること

### Phase 4: 自作 sync の縮小

- instructions / agents / rules の runtime sync を削除し、doctor の検品を `apm.lock.yaml` の `deployed_files` ベースへ切り替える
- 残留させる対象を明記する: model-policy（判断ポイント 1）、host-local MCP、Pi 向け sync、agmsg roster の退避・復元
- ゲート: `mise run verify`（bats / Pester 両 suite 含む）と `mise run deploy` が green で、doctor が新経路のみで完結すること

### Phase 5: 仕上げ

- `catalog/README.md`、ルート `AGENTS.md` の Ownership 表、`docs/skill-inventory.md` 等の記述を新配置へ更新する
- `apm pack` で plugin bundle として配れるか試し、必要なら `apm-policy.yml` の導入を別 Issue で検討する

## 影響範囲（実装時に触るもの）

- `scripts/apm-workspace.sh` / `.ps1`: `tracked_catalog_*` / `copy_managed_*` / staging / doctor のパスと検品ロジック
- `mise/catalog.toml` ほか mise タスク定義、`.gitignore`（`catalog/.apm` の扱い）
- `tests/`: catalog staging と conformance の fixture
- lint: `lint-frontmatter`（instructions の `description` 必須チェック追加）、`lint-catalog-leaks` の対象パス
- ドキュメント: `catalog/README.md`、ルート `AGENTS.md`、`docs/skill-inventory.md`

## ロールバック

- 各 Phase は独立したコミットに分け、`git revert` でその Phase だけ戻せるようにする
- Phase 3 以前は旧配置と新配置が併存可能な期間を設け、lock の `deployed_files` 比較で欠落が出たら次 Phase へ進まない

## 完了条件

1. 素の consumer が `apm install` のみで skills / instructions / agents を取得できる（`package_type: apm_package`）
2. `mise run verify` と `mise run deploy` が green
3. doctor が自作 sync に頼らず新経路で検品できる
4. 判断ポイント 3 件が全て決着し、残留する自作 sync の範囲がドキュメントに明記されている
