# RTK (Rust Token Killer)

RTK の運用ルールはすべて `$rtk` skill を source of truth とする。`catalog/AGENTS.md` には RTK のルールを置かない（ユーザーが明示したときだけ使う手動検証ツールのため、常時ロードする guidance から除外している）。

この rule file は Claude / rules 配布先向けの薄い導線として残す。詳細なコマンド表、filter 方針、Codex 固有の setup は skill 側へ集約する。
