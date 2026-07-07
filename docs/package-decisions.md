# Package Decisions

採用・撤去・見送りにした APM パッケージの意思決定ログ。1 パッケージ 1 セクション。
「なぜ入れたか / なぜ消したか / 再検討するなら何を見るか」を残す。

## ponytail (DietrichGebert/ponytail)

- **Status: 撤去（2026-07-07）**
- 経緯: 2026-07-03 に managed lane から manual-skills lane へ移行 → 2026-07-07 に全面撤去。
  skills は `manual-skills/.apm/skills/` から削除、手動管理だった hooks は
  `~/.claude/settings.json` と `~/.claude/hooks/ponytail/` から削除、
  孤児化した `apm_modules/DietrichGebert/ponytail` checkout も削除。
- 撤去理由:
  - `ponytail:` self-tagging コメント規約が実運用で誤発火（実セッションで 3/3 が誤用 —
    「上限付きの近道」ではなく単なる設計理由の説明に使われた）。
    モデルに名前付きトリガーを与えると表層マッチで過剰適用する既知の傾向
    （over-refusal / moderation over-sensitivity 系の研究と同型）に合致。
  - 独自タグはチームメイトに読めない語彙でレビュー時のノイズになる。
  - 有用部分（YAGNI ladder）は短いプロンプトで再現可能。
    検証: https://blog.scottlogic.com/2026/06/16/ponytail-yagni-and-the-problem-with-prompt-benchmarks.html
  - 判断基準: 「悩むぐらいなら使わない」。
- 再検討するなら: コメントタグ指示を除いた trimmed persona にするか、
  設計の壁打ちには `/grilling`（mattpocock/skills）を使う。

### 副産物の教訓: APM は Claude Code hooks 付きパッケージを壊して deploy する

ponytail 固有ではない、hooks を持つ任意のパッケージに再発しうる問題（2026-07-03 時点）:

- APM の managed rollout は package の `copilot-hooks.json` 形式
  (`bash`/`powershell`/`timeoutSec`) を `SessionStart`/`UserPromptSubmit` に変換してしまい、
  package 自身の `claude-codex-hooks.json` (`matcher`+`hooks`+`command`/`timeout`) を使わない。
  結果、`/doctor` が invalid hook JSON を報告する。
- `apm.lock.yaml` の `deployed_files` は hook のエントリポイントだけ追跡し、
  エントリポイントが `require()` する兄弟モジュールを配布しないため、
  deploy 後に `MODULE_NOT_FOUND` でクラッシュする。
- 回避策: hooks を持つパッケージは manual lane 化し、hooks は upstream checkout から
  全ファイルを手動コピーして各 target の hook config を直接管理する。
  信頼する前に `update-config` skill の "Constructing a Hook" の pipe-test を通すこと。
