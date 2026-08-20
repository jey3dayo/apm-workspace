# Phase 2: agmsg roster save/restore を apply の interface に内蔵する

architecture review 候補2。/improve #1(copy 失敗時の rm -rf)は 2026-08-21 に別途修正済み(worker-improve-0821)。証拠: `tmp/apply-audit-20260821/report.md` §3。

## 現状の問題(検証済み)

- `mise.toml:37-66`: apply の `depends`/`depends_post` に save/restore が配線されているが、**apply 失敗時に depends_post が走らず roster が unlink のまま残る**(mise.toml:53-58 のコメントで既知と明記)
- `agmsg:state:save/restore` タスクは `run_windows` が無く **Windows でも bash 前提**
- `apply:skills:local`(Codex skill tree を直接 swap)には save/restore の配線が**無い**
- PS 側 `Invoke-Apply` に state 処理は皆無(ps1 全文に agmsg の文字列なし)

## 変更内容

### 1. `scripts/apm-workspace.sh` — cmd_apply に内蔵

- 冒頭で `scripts/agmsg-state.sh save` を呼ぶ
- 既存の `trap 'rm -rf "$apply_stage_root"' RETURN`(sh:972)に restore を追加し、**成功・失敗の全経路で restore が走る**ようにする(restore は冪等: 既存 symlink は張り直しのみ)

### 2. `scripts/apm-workspace.ps1` — Invoke-Apply に内蔵

- **確定(2026-08-20 設計返答)**: Windows は bash 前提にしない。agmsg-state 相当を **PowerShell へ移植**し(save/restore/absorb のロジックは56行の小規模)、`mise.toml` の `agmsg:state:*` タスクにも `run_windows` を追加する
- try/finally の finally 節へ restore を追加。両 adapter が自前完結すること

### 3. `mise.toml` — depends/depends_post を recovery 用へ降格

- `[tasks.apply]` から `depends`/`depends_post` を外すか、restore の冪等性を前提に残すかを選ぶ。**推奨: 外して、`agmsg:state:restore` を手動 recovery タスクとして残す**。mise.toml:53-58 のコメントを新しい契約(apply 内蔵・restore は recovery adapter)へ書き換える
- `apply:skills:local` 側は apply 本体(cmd_sync_local_skills / Invoke-SyncLocalSkills)にも同じ save/restore を内蔵する

### 4. テスト

- Bats: 「apply が途中で fail しても `$HOME/.agents/skills/agmsg/db` の symlink が復元されている」fixture(fake HOME + 故意に fail する step)
- 二重 restore(内蔵 + 手動)の冪等性テスト

## リスク

- restore の二重実行は冪等性が前提。agmsg-state.sh の restore は「症状なし」を確認済みだが、テストで固定する
- worker 実行中の deploy は roster を一瞬 unlink する。既存挙動と同じだが、内蔵化で窓は短くなる

## 完了条件

apply の任意の失敗地点で roster symlink が生存し、`apply:skills:local` も同じ保証を持つ。mise.toml の既知課題コメントが解消される。
