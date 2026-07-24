# SaaS Connectors

SaaS 連携の接続状況インベントリと配置優先度。各アプリの接続状況が変わったらここを更新する。
採用・撤去の意思決定ログは `docs/package-decisions.md` に書き、ここには現在状態だけを持つ。

## 配置優先度

SaaS への接続手段は次の優先順で選ぶ。上位が使えるなら下位で二重管理しない。

1. アプリ側プラグイン / コネクタ — claude.ai の managed MCP コネクタ、ChatGPT アプリのプラグイン。認証・トークン更新・ツール定義のメンテナンスがアプリ側に集約される
2. `apm.yml`（external skill / MCP） — アプリ側コネクタが無い、または headless / CLI 常用で必要な場合のみ
3. `catalog/skills`（自作スキル） — 上記で賄えない固有ワークフローだけ

コネクタと役割が被らないスキル（例: `slack-app-management` は Slack アプリ管理で SlackDB コネクタとは別役割）は撤去対象にしない。

片側のアプリにしかプラグインが無い場合（例: superpowers は Codex プラグインのみで Claude には無い）は、APM 管理にして両方へ配ってよい。両側にコネクタが揃ったら撤去を検討する。

## 接続状況（2026-07-11 時点）

○ = 接続済み / × = 未接続・非提供 / △ = 接続に問題あり

| SaaS            | Claude (claude.ai コネクタ)     | Codex (ChatGPT プラグイン) | APM 側の扱い                                   |
| --------------- | ------------------------------- | -------------------------- | ---------------------------------------------- |
| Linear          | ○                               | ○                          | 撤去済み（2026-07-10、package-decisions 参照） |
| Sentry          | ○                               | ○                          | 撤去済み（2026-07-10、package-decisions 参照） |
| GitHub          | ○                               | ○                          | `gh` CLI 併用                                  |
| Gmail           | ○                               | ○                          | —                                              |
| Google Calendar | ○                               | ○                          | —                                              |
| Google Drive    | ○                               | ×                          | —                                              |
| Datadog         | ○                               | ×                          | —                                              |
| Slack           | ○（SlackDB / Slack は要再接続） | ×                          | `slack-app-management` は別役割で維持          |
| Snowflake       | △（接続の問題）                 | ×                          | —                                              |
| Excalidraw      | ○                               | ×                          | —                                              |
| 社員情報検索    | △（要再接続）                   | ×                          | `mdb-api` スキルは API 実装レビュー用で別役割  |
