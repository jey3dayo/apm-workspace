# AI agent 委譲フロー図

AI agent の委譲・引き継ぎフローを Archify の仕様ファイルと閲覧用 HTML で保管しています。

## orchestrator-worker

- [閲覧用 HTML](./orchestrator-worker.html)
- [Archify 仕様](./orchestrator-worker.workflow.json)

2026-09-07 に `deliver`（showcase）と `visual-check` を通過済みです。receipt と確認用スクリーンショットは 2026-11-03 にリポジトリから外しており、履歴は git に残っています。

図の読み方は次のとおりです。

- ノードの色は役を表します。凡例のラベルは `meta.legend.entries` で役名へ差し替えており、既定の `User UI` のような汎用名は使っていません。
- パレットは役と共有する 7 色しかなく同じモデルが複数の役に現れるため、コスト帯は色で表しません。コスト帯はカード内の項目順とラベルで示しています。

## 削除済みの図

`agmsg-delegation` の図（閲覧用 HTML と Archify 仕様）は `agmsg` 依存の撤去（#150）に合わせてスキルごと削除しました。履歴は git に残っています。
