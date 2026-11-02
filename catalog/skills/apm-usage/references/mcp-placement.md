# MCP 配置方針

global MCP はリポジトリをまたいで常時使う基盤だけに限定し、それ以外は repo-local または on-demand にする。global の実体は root `apm.yml` の `mcp:` が source of truth で、固定リストはどこにも持たない。

- MCP 設定を永続変更する前に `apm-usage` の MCP ownership gate を通す。SaaS 接続の優先順（アプリ側コネクタ > `apm.yml` > skill）と理由は `~/.apm/docs/saas-connectors.md` が正本
- current docs は `context7`、広い比較調査は `web-research`（URL 取得と Web 検索は global AGENTS.md「コマンド選択」の表）
- MCP として repo-local 追加が必要なブラウザ系は `chrome-devtools` のみ（使い分けは global AGENTS.md「ブラウザ操作の選択」表）。デスクトップ / OS レベルのスクリーンショットは `screenshot` スキル
