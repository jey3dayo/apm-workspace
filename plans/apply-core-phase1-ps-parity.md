# Phase 1: PowerShell apply/validate を Bash とパリティ化する

/improve #7 と architecture review 候補1の前半。証拠の正本: `tmp/apply-audit-20260821/report.md`(全主張を行番号付きで検証済み)。

## 前提と仮定(実装前に確認)

- **canonical 順序は Bash 側**とする: stage → MCP install → MCP normalize → **compile** → asset 配布 → swap → legacy 掃除 → private overlay(`apm-workspace.sh:974-985`)。PS 側(compile が swap 後・try/finally 外)は後発の逸脱とみなす
- Windows の Claude private skill symlink は、symlink 権限が無い環境を考慮し **copy 方式の fallback** を実装する(junction はディレクトリ単位のため skill 単位 copy が単純)
- 実装統合(bash core 一本化)は Phase 4 で判断。本 Phase は両実装を残したままドリフトだけ解消する

## 変更内容

### 1. `scripts/apm-workspace.ps1` — Invoke-Apply へ private skill sync 移植

Bash 側の対応物: `sync_private_skills_into_targets`(sh:1011-1027)、`private_skill_records`(sh:998-1004)、Codex 側 stage/swap(sh:1029-1064)、Claude 側 symlink sync + stale 掃除(sh:1075-1121)。

- `Get-PrivateSkillsRoot`(ps1:1824-1826)は既存。これを起点に `Sync-PrivateSkillsIntoTargets` を新設し `Invoke-Apply` の最終ステップへ追加
- Claude 側: symlink 作成を試み、失敗時(権限なし)は copy + 警告出力へ fallback
- stale 掃除(bash の `cleanup_stale_claude_private_skill_symlinks` 相当)も移植

### 2. `scripts/apm-workspace.ps1` — Invoke-Validate へ target-tree 検証追加

- Bash の `validate_codex_skill_target_tree`(sh:716-729)相当の `Test-CodexSkillTargetTree` を新設: `$HOME/.agents/skills` 配下の 4 階層以上ネストした `*/skills/*/SKILL.md` / `*/.apm/skills/*/SKILL.md` を検出したら fail
- `Invoke-Validate`(ps1:1785-1790)の最終ステップへ追加

### 3. `scripts/apm-workspace.ps1` — Invoke-Apply の実行順を canonical へ

現状(ps1:1642-1657): stage → **asset 配布** → MCP install → MCP normalize → swap → legacy 掃除 → (finally) → **compile** → pi-instructions。

- `Sync-ManagedCatalogRuntimeAssets` を MCP normalize と swap の間へ移動
- `Invoke-CodexCompile` を try/finally **内**・asset 配布の**前**へ移動(bash: MCP normalize 直後)
- 最終順: stage → MCP install → MCP normalize → compile → asset 配布 → pi-instructions → swap → legacy 掃除 → private sync

### 4. テスト更新

- Pester の順序 regex(`Tests.ps1:859-866`)は PS 側で compile / asset を検証対象に含めない盲点がある。新順序に合わせて **compile と asset を含む形へ強化**(Phase 3 で fixture に置換予定だが、それまでの契約固定として)
- private sync / target-tree 検証の Pester テストを新設(現状 0 件。fake HOME fixture で実行検証)

## 検証

`mise run check`、Pester 全件、Bats 全件、`git diff --check`。可能なら Windows 実機 or pwsh -Platform で symlink fallback 経路の単体確認。

## リスク

- PS の順序変更は Windows ユーザーの挙動変更。compile 入力の状態が変わるため、deploy 後に `mise run doctor` で成果物確認
- symlink fallback(copy)は staleness を持ち込む。copy 経路に入ったことを必ず警告出力する

## 完了条件

report.md §1-§2 の非対称 3 点(private sync / target-tree / 順序)がすべて解消し、新テストが両経路を固定している。
