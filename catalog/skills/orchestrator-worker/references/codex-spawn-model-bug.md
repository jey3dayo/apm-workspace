# Codex `gpt-5.6-sol` spawn_agent モデル指定バグ

既知の制限(2026-08 時点)。解消されたら本ファイルと SKILL.md の参照行を更新すること。

## 症状

`gpt-5.6-sol` はモデルメタデータで MultiAgent V2 を選択し、V2 のデフォルト `hide_spawn_agent_metadata = true` が `spawn_agent` スキーマから `agent_type` / `model` / `reasoning_effort` / `service_tier` を隠す。この結果 Sol から spawn したサブエージェントは明示指定してもすべて Sol を継承し、`gpt-5.6-luna` は選択できない(`openai/codex` issue #31814, #34964 ほか多数)。`gpt-5.6-terra` への委譲も同様に効かないため、実質的に Sol からのモデル指定委譲は機能しない。

## 回避策(優先順)

1. `~/.codex/config.toml` で `multi_agent_v2 = false` にして V1 へ固定する(`model_catalog_json` で対象モデルの `multi_agent_version` を `"v1"` に上書きしたカタログを使う)
2. それも使えない場合は `agmsg-delegation` スキル(agmsg + herdr による別プロセス Worker)の手動起動をユーザーに提案する
