# AI agent 委譲フロー図

- 最終更新: 2026-09-07
- 対象: APM の AI agent 協働フローを後から確認する人
- タグ: `category/architecture`, `audience/developer`

このディレクトリには AI agent の委譲・引き継ぎフローを Archify の仕様と閲覧用 HTML で保管しています。

## すぐ見る

- [orchestrator-worker の閲覧用 HTML](./orchestrator-worker.html)

agmsg-delegation の図（閲覧用 HTML と Archify 仕様）は、agmsg 依存の撤去（#150）に合わせてスキルごと削除しました。履歴は git に残っています。

## orchestrator-worker

- [閲覧用 HTML](./orchestrator-worker.html)
- [Archify 仕様](./orchestrator-worker.workflow.json)
- 状態: 2026-09-07 に `deliver`（showcase）と `visual-check` を通過済みです。receipt と確認用スクリーンショットは 2026-11-03 にリポジトリから外しました（git 履歴に残っています）。
- ノードの色は役を表します。凡例のラベルは `meta.legend.entries` で役名へ差し替えています（既定は `User UI` などの汎用名で、役を示しません）。
- パレットは役と共有の 7 色しかなく同じモデルが複数の役に現れるため、コスト帯は色で表しません。コスト帯はカード内の項目順序とラベルで示します。
