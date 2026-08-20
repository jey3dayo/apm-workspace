# /improve 指摘バックログ(plan-only 分)

2026-08-21 の /improve 引き継ぎ(#1-#13)のうち、即時実装(#1 #2-HOME化 #3 #4 = worker-improve-0821)と Phase 計画(#7 = apply-core-phase1)に含まれない残り。

## ユーザー判断待ち

- #8 Jina bearer の rotation: `.mcp.json` は chmod 600 済み・gitignore 済み(2026-08-21)。平文 bearer の rotation はユーザー操作が必要

## 完了

- #5 ca-pass の global 撤去(2026-08-21): ユーザー承認のうえ `apm.yml` から撤去、`apm lock` 再解決、deploy で両配布先から消滅を確認。`docs/package-decisions.md` へ実撤去を追記済み
- #7 PS apply/validate のパリティ化(2026-08-21): apply-core Phase 1 として解消(`eb3a4ce`)
- #11 CI path filter へ `optional-skills/**` 追加(2026-08-21)

## 小粒(次の worker バッチ候補、いずれも独立)

- #6 commands/rules がマージコピー(`apm-workspace.sh:2217-2226`): 配布先で管理外ファイルと混ざる。swap 方式(stage → replace)へ寄せるか、管理 manifest で掃除対象を特定する設計判断が先
- #9 `cp -RL` が skill 内 symlink を無条件に辿る(`apm-workspace.sh:2104`): ループ・意図しない実体化のリスク。`-RL` → `-R` + 明示解決の影響調査から
- #10 cache repair の削除先が文字列 prefix 判定のみ(`apm-workspace.sh:1150-1159`): `is_path_under_dir` 相当の正規化済み判定へ
- #12 PS quick-sync が古いファイルを残し、Pester `:1229` がその挙動を期待: 実装とテストの同時修正。Phase 3 fixture 導入済みのため着手可能

## docs(まとめて 1 回)

- #13 inventory / `llms.txt` / TODO の二重管理 drift: #5 の決着後に `docs-review` でまとめて同期

## 見送り確定(再監査しない)

catalog agent 本文の命令調 / pwsh・Pester の mise 非管理 / `mise run test` 直列 / screenshot の deprecated 依存継続。
