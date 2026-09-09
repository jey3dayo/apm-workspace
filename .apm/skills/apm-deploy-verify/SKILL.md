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
2. `mise run deploy:fresh` を実行する。`install:catalog` 単独では新規追加ファイルが配布先から消えるため使わない。**注意:** opencode の deploy root が `.opencode` から `~/.config/opencode` へ変わった契約への移行後、初回 deploy は `~/.config/opencode/{skills,agents}` の既存内容を削除する。事前 archive はこのスキルの担当外であり、呼び出し元（Orchestrator）が deploy 前に行う
3. 変更した skill ごとに配布一致を確認する:

   ```bash
   diff -rq ~/.claude/skills/<skill> ~/.agents/skills/<skill>
   diff -q <catalog>/skills/<skill>/SKILL.md ~/.claude/skills/<skill>/SKILL.md
   ```

   これに加えて opencode 面の配布一致を確認する。opencode は skills を `.config/opencode/skills` からは読まず `.claude/skills` / `.agents/skills` から読むため、上記の `~/.agents/skills` 一致確認がそのまま opencode の canonical skills face の検証にもなる。

   ```bash
   # negative: opencode 用 skills 面は存在してはいけない（二重配布の復活を検知する）
   [ ! -e ~/.config/opencode/skills ]

   # positive: opencode の agents は catalog と full-tree swap で厳密一致する（余剰・欠落なし）
   diff -rq <catalog>/agents ~/.config/opencode/agents

   # positive: opencode の commands は catalog が提供するファイルだけを個別比較する。
   # commands は manifest scope 配布（sync_managed_catalog_dir_with_manifest）のため、
   # `.managed-catalog-manifest` や同居する非 catalog ファイルが配布先にだけ存在するのは仕様であり、
   # ディレクトリ全体の厳密一致では必ず失敗する
   fail=0
   while read -r f; do
     rel=${f#<catalog>/commands/}
     diff -q "$f" ~/.config/opencode/commands/"$rel" || fail=1
   done < <(find <catalog>/commands -type f ! -name '.gitkeep')
   [ "$fail" -eq 0 ]

   # apm.yml の targets に opencode が再混入していないこと
   ! grep -qx '  - opencode' apm.yml
   ```

4. agmsg roster link の到達性を確認する。確認対象は canonical face のみ。判定は `db` / `teams` の個別状態を見て `ls -l` でその場で二分するのではなく、両方を見た集約結果を持つ `~/.apm` の `mise run doctor` に一元化する:

   ```bash
   cd ~/.apm && mise run doctor
   ```

   他の face（`~/.claude/skills/agmsg` など）に `db` / `teams` が無いのは仕様であり、張ってはいけない。doctor の agmsg 判定に応じて対応する:
   - db/teams とも symlink で正しい target を指していれば通過
   - doctor の復旧推奨に `mise run agmsg:state:restore` が**含まれない**（plain path を含む集約結果）場合は実行しない。db または teams のどちらかが symlink ではなく plain なディレクトリ/ファイルで、断線中に書かれた roster 更新を保持している可能性があり、restore は state root 側で上書きし discard しうる（同名ファイルは store 優先でマージされ、plain 側は削除される）。先に中身を `${XDG_STATE_HOME:-$HOME/.local/state}/agmsg/<name>` と手動で突き合わせ、必要な差分を反映してから relink する
   - doctor の復旧推奨に `mise run agmsg:state:restore` が含まれる（missing / dangling / wrong-target のみで plain path が無い）場合は、失うものが無いのでそのまま `~/.apm` で実行してよい。手で `ln -s` を張らない

5. `agmsg-delegation` の runtime asset（scripts/・WORKER.md・agmsg-review.config.toml）を変更した場合のみ smoke を実行する。項目と合否基準は `agmsg-delegation` Preflight の「初回利用前の smoke 5点」が正本
6. smoke の合否判定は worker モデルの自己申告でなく、ファイルシステムの実体で行う（touch したファイルの存在確認、拒否されるべき書込先にファイルが無いこと）。worker は書込失敗時でも成功を報告した実績がある

## 報告

- 実行したコマンドと結果（通過 / 失敗）を列挙する
- 配布一致は skill 名ごとに一致 / 不一致を明記する
- agmsg roster link は canonical face の `db` / `teams` の symlink 先を明記する
- smoke を実行した場合は、実体確認したパスと結果を添える
- 失敗があっても自分で修正しない。失敗ログをそのまま呼び出し元へ返す

完了条件: 全コマンドの結果と配布一致の判定を、実体確認の根拠付きで報告した。
