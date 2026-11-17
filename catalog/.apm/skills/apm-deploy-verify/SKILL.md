---
name: apm-deploy-verify
model: haiku
context: fork
agent: implementer
background: false
description: >-
  APM workspace の checkout で catalog を変更した後の機械的な検証一式（format / check /
  配布先の内容一致）を実行する。
  「検証して」「配布一致を確認して」で使う。配布そのものは実行しない（配布は docs/native-distribution.md の B）。
  何を変更するか・どこが正本かの判断は apm-usage が正本。本スキルは実行と結果報告だけを担う。
---

# APM Deploy Verify

catalog 変更後の検証は判断を含まない機械作業なので、Orchestrator（fable / opus）は自分で実行せず本スキルへ委譲する。変更内容の設計判断・修正方針の決定は呼び出し元に返す。

検証対象は呼び出し元の cwd によらず常に APM workspace の authoring checkout（`~/src/github.com/jey3dayo/apm-workspace`。以下 `<checkout>`）である。他の repo から呼ばれても、以下のコマンドはすべて `cd <checkout>` したシェルで実行する（`<catalog>` は `<checkout>/catalog`）。

実 HOME は native（`~/.apm/apm.yml` の 1 行目が `# Rendered by scripts/native.sh`）で、旧経路の `deploy` 系 task は 2026-11-10 に退役した。本スキルは配布を実行しない。配布は呼び出し元が `docs/native-distribution.md` の B で行い、手順 3 の配布一致は、その B6 のあとに見る。

fork 実行では会話履歴は見えない。検証対象（変更した skill）は ARGUMENTS があればそれ、無ければ `git -C <checkout> status --short` / `git -C <checkout> diff` から決める。

ログを残すときは `<checkout>/tmp/` に置く（`$HOME` 直下や repo 外には作らない）。ログへ `tee` するコマンドの終了コードは、`set -o pipefail` で取る（pipe の終了コードは最後のコマンドのものになり、失敗を取り逃す）。Bash ツールのシェルは zsh で、`PIPESTATUS` は空になる（zsh は `pipestatus`）。

## 手順

1. `mise -C <checkout> run format` → `mise -C <checkout> run check` を実行する。失敗したら以降へ進まず、失敗ログを添えて報告する
2. 配布済みかどうかを、次の比較で決める（呼び出し元には聞かない）:

   ```bash
   head -1 ~/.apm/apm.yml
   git -C <checkout> rev-parse HEAD
   ```

   1 行目は `# Rendered by scripts/native.sh ... pinned at <sha>. ...` の形で、`<sha>` が `git rev-parse HEAD` と一致すれば配布済み。一致しないとき（1 行目が別の形のときも）は手順 3 の配布一致を判定できないので、両方の値を添えて「配布前のため未実行」と報告して終える。

3. 変更した skill ごとに配布一致を確認する:

   ```bash
   diff -rq ~/.claude/skills/<skill> ~/.agents/skills/<skill>
   diff -q <catalog>/.apm/skills/<skill>/SKILL.md ~/.claude/skills/<skill>/SKILL.md
   ```

   workspace-only skill（`.apm/skills/<id>`）は `~/.claude/skills` / `~/.agents/skills` へ配布されないので上の diff は使わない。代わりに、workspace の `.claude/skills/<id>` と `.agents/skills/<id>` が symlink で、`readlink -f .claude/skills/<id>` / `readlink -f .agents/skills/<id>` がどちらも `.apm/skills/<id>` の絶対パスと一致し、`.apm/skills/<id>/SKILL.md` が存在することを確認する。

   これに加えて opencode 面の配布一致を確認する。opencode は skills を `.config/opencode/skills` からは読まず `.claude/skills` / `.agents/skills` から読むため、上記の `~/.agents/skills` 一致確認がそのまま opencode の canonical skills face の検証にもなる。

   ```bash
   # negative: opencode 用 skills 面は存在してはいけない（二重配布の復活を検知する）
   [ ! -e ~/.config/opencode/skills ]

   # negative: opencode 用 agents 面も存在してはいけない。catalog agents は Claude 形式
   # （`tools` はカンマ区切り文字列、`color` は名前色）で、opencode のスキーマ検証
   # （`tools` は object、`color` は hex）に適合せず、1ファイルでも入ると opencode が
   # 起動を拒否する。opencode は agents face を opt-out している
   [ ! -e ~/.config/opencode/agents ]

   # negative: codex 用 agents 面も存在してはいけない。codex-cli は
   # `~/.codex/agents/*.toml` しか読まず、catalog agents の Claude 形式 `.md` は
   # 無視されるだけなので、codex も agents face を opt-out している
   [ ! -e ~/.codex/agents ]

   # apm.yml の targets に opencode が再混入していないこと
   ! grep -qx '  - opencode' apm.yml
   ```

対象外: `mise -C <checkout> run doctor` が担う診断（workspace と配布状態の読み取り専用チェック）は本手順に含めない。doctor の実行と結果の扱いは `apm-usage` の管轄とする。旧 `agmsg-delegation` 向けの roster link 確認と runtime asset の smoke も、agmsg 依存の撤去で対象スキル自体が無くなったため含めない。

## 報告

- 実行したコマンドと結果（通過 / 失敗）を列挙する
- 配布一致は skill 名ごとに一致 / 不一致を明記する
- 失敗があっても自分で修正しない。失敗ログをそのまま呼び出し元へ返す

完了条件: 全コマンドの結果と配布一致の判定を、実体確認の根拠付きで報告した。
