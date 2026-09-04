# Codex spawn_agent の Luna 対応履歴

0.147.0 で解消された制限の記録。以降の Codex では本文の制約は無い。

## 現在の状態

Codex CLI 0.147.0 では、V2 の親が明示的に無効化されていない可視モデルを起動できるようになった。
Luna は leaf worker として実装を担当できるが、自身の collaboration tools は公開されず、再帰的な委譲は行えない。
この変更は [openai/codex PR #36892](https://github.com/openai/codex/pull/36892) と
[0.147.0 release](https://github.com/openai/codex/releases/tag/rust-v0.147.0) に含まれる。

## 旧症状

0.144.6〜0.145.0 では、`gpt-5.6-luna` はモデルカタログ上 MultiAgent V1 とマークされており、
V2 で動く親（`gpt-5.6-sol` / `gpt-5.6-terra`）からの
`spawn_agent(model: "gpt-5.6-luna")` は `Unknown model` で拒否されていた
（`openai/codex` issue #35097、2026-07-24 起票）。

## 初期の別症状（記録として残す）

初期の報告では、sol がモデルメタデータで MultiAgent V2 を選択し、V2 のデフォルト `hide_spawn_agent_metadata = true` が `spawn_agent` スキーマから `agent_type` / `model` / `reasoning_effort` / `service_tier` を隠すため、明示指定してもサブエージェントがすべて Sol を継承する挙動だった（issue #31814, #34964）。#35097 の明示拒否はこれより後の codex での挙動で、症状は違えどいずれも spawn_agent 経由では luna に到達できない。

## 現行の対応

1. Codex native の `spawn_agent` で Luna を leaf worker として起動する
2. native spawn が使えない環境、別セッション・別プロセスへの引き継ぎ、または外部プロセス分離が必要な場合だけ `agmsg-delegation` を使う
3. `multi_agent_v2 = false` での V1 固定や `model_catalog_json` の上書きは、カタログ改変に当たるため使わない
