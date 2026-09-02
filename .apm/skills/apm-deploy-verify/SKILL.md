---
name: apm-deploy-verify
model: sonnet
description: >-
  ~/.apm の catalog を変更した後の機械的な検証一式（format / check / deploy:fresh /
  配布先の内容一致 / agmsg-delegation runtime asset の smoke）を実行する。
  「配布して検証して」「deploy 検証」「smoke 回して」「配布一致を確認して」で使う。
  何を変更するか・どこが正本かの判断は apm-usage、smoke の合否基準は
  agmsg-delegation が正本。本スキルは実行と結果報告だけを担う。
---

# APM Deploy Verify

catalog 変更後の検証は判断を含まない機械作業なので、Orchestrator（fable / opus）は自分で実行せず本スキルへ委譲する。変更内容の設計判断・修正方針の決定は呼び出し元に返す。

## 手順

1. `mise run format` → `mise run check` を実行する。失敗したら以降へ進まず、失敗ログを添えて報告する
2. `mise run deploy:fresh` を実行する。`install:catalog` 単独では新規追加ファイルが配布先から消えるため使わない
3. 変更した skill ごとに配布一致を確認する:

   ```bash
   diff -rq ~/.claude/skills/<skill> ~/.agents/skills/<skill>
   diff -q <catalog>/skills/<skill>/SKILL.md ~/.claude/skills/<skill>/SKILL.md
   ```

4. `agmsg-delegation` の runtime asset（scripts/・WORKER.md・agmsg-review.config.toml）を変更した場合のみ smoke を実行する。項目と合否基準は `agmsg-delegation` Preflight の「初回利用前の smoke 5点」が正本
5. smoke の合否判定は worker モデルの自己申告でなく、ファイルシステムの実体で行う（touch したファイルの存在確認、拒否されるべき書込先にファイルが無いこと）。worker は書込失敗時でも成功を報告した実績がある

## 報告

- 実行したコマンドと結果（通過 / 失敗）を列挙する
- 配布一致は skill 名ごとに一致 / 不一致を明記する
- smoke を実行した場合は、実体確認したパスと結果を添える
- 失敗があっても自分で修正しない。失敗ログをそのまま呼び出し元へ返す

完了条件: 全コマンドの結果と配布一致の判定を、実体確認の根拠付きで報告した。
