# Phase 3: conformance fixture — コマンド interface をテスト面にする

architecture review 候補3。**実行順 3(本 Phase)→1→2 は 2026-08-20 の設計返答で承認済み**。fixture を先に作り、現状ドリフトを固定してから Phase 1 で直す。CI を green に保つため、PS 側のドリフト検出 assert は Phase 1 完了までは skip マーク + Phase 1 計画への参照コメントで保留する(ドリフトの記録と suite の green を両立)。

## 現状の問題(検証済み、report.md §4)

- ソーステキスト regex assert: Bats 3件(`apm-workspace.sh.bats:179-182, 184-187, 222-228`)、Pester 6件(`Tests.ps1:853-857, 859-866, 932-936, 938-946, 948-966, 1300-1358`)
- 特に Tests.ps1:859-866 の順序 regex は PS 側で `Invoke-CodexCompile` / `Sync-ManagedCatalogRuntimeAssets` を検証対象に含めず、実在する順序ドリフトを構造的に検出できない
- `cmd_apply` / `Invoke-Apply` / `cmd_validate` / `Invoke-Validate` 全体を実行ベースで検証するテストは 0 件

## 変更内容

### 1. 共有 fixture(tests/conformance/ 配下に新設)

- fake HOME(mktemp): `.agents/skills`, `.claude/skills`, `.codex` の空ツリー
- recording fakes: PATH 先頭に置く `apm` / `git` / `codex` の stub スクリプト。呼び出しを引数ごとにログへ記録し、`apm compile` 等は成果物のダミーを出力
- 最小 workspace fixture: `apm.yml` + catalog 最小構成 + private-skills 1 件

### 2. conformance テスト本体

- Bash: `bash scripts/apm-workspace.sh apply` を subprocess 実行 → 期待ツリー(配布先の skill 構成、private overlay の存在、呼び出し順ログ)を assert
- PS: `pwsh scripts/apm-workspace.ps1 apply` に**同一の期待値**を課す
- validate も同様(target-tree 検証が両実装で fail することを nested fixture で確認)
- 期待値は 1 箇所(共有 fixture)に置き、両 adapter のテストから参照する

### 3. ソース regex assert の削除

fixture が両実装で green になった後に、上記 Bats 3件・Pester 6件を削除する。削除は fixture 導入と同一 PR にせず、fixture 稼働を1サイクル確認してから。

## リスク

- recording fakes の初期実装コスト(apm CLI の呼び出し面を洗う必要がある)。まず apply だけに絞り、validate は次サイクル
- CI 実行時間の増加。subprocess 実行 2 本 × fixture 準備。`mise run test` の直列制約(共有 deploy 面)は既存のまま

## 完了条件

同一期待値を両 adapter に課す fixture が CI で走り、report.md §1 のドリフトが fixture の failing case として再現される(Phase 1 完了後に green 化)。
