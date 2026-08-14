# Codex spawn_agent の luna 指定制限（sol / terra 共通）

既知の制限(2026-08 時点)。解消されたら本ファイルと SKILL.md の参照箇所を更新すること。

## 現在の症状

`gpt-5.6-luna` はモデルカタログ上 MultiAgent V1 とマークされており、V2 で動く親（`gpt-5.6-sol` / `gpt-5.6-terra`）からの `spawn_agent(model: "gpt-5.6-luna")` は `Unknown model gpt-5.6-luna for spawn_agent. Available models: gpt-5.6-sol, gpt-5.6-terra` で拒否される（`openai/codex` issue #35097、2026-07-24 起票）。ローカルの model catalog を v1→v2 に書き換えれば技術的には子として動くが、OpenAI の Codex DX エンジニアが「MultiAgent V2 が要求するエージェント間の proactive な通信は Sol と Terra しかうまくできない。カタログ改変での強制は非推奨」と、意図的な制限であることを明言している（@pvncher、2026-07-31、<https://x.com/pvncher/status/2083300990350954981>）。

## 旧症状（記録として残す）

初期の報告では、sol がモデルメタデータで MultiAgent V2 を選択し、V2 のデフォルト `hide_spawn_agent_metadata = true` が `spawn_agent` スキーマから `agent_type` / `model` / `reasoning_effort` / `service_tier` を隠すため、明示指定してもサブエージェントがすべて Sol を継承する挙動だった（issue #31814, #34964）。#35097 の明示拒否はこれより後の codex での挙動で、症状は違えどいずれも spawn_agent 経由では luna に到達できない。

## 対応（優先順）

1. luna への委譲は `agmsg-delegation` スキル（別プロセスの `codex -m gpt-5.6-luna exec`。spawn_agent 非経由のため制限を受けない）を標準経路とする
2. `multi_agent_v2 = false` での V1 固定や `model_catalog_json` の上書きは、OpenAI が非推奨と明言したカタログ改変に当たるため使わない
