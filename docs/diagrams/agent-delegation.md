# 📚 AI agent 委譲フロー図

**最終更新**: 2026-09-07
**対象**: APM の AI agent 協働フローを後から確認する人
**タグ**: `category/architecture`, `audience/developer`, `tool/agmsg`

このディレクトリでは、AI agent の委譲・引き継ぎフローを Archify の仕様と閲覧用 HTML で保管する。

## すぐ見る

- [agmsg-delegation の閲覧用 HTML](./agmsg-delegation.html)
- [orchestrator-worker の閲覧用 HTML](./orchestrator-worker.html)

## agmsg-delegation

- [閲覧用 HTML](./agmsg-delegation.html)
- [Archify 仕様](./agmsg-delegation.workflow.json)
- 状態: HTML と Archify 仕様を生成済み。visual-check の receipt はリポジトリに無く、
  `deliver` の通過記録も残っていない（初出コミット 846aadc 以降、検証成果物の追加なし）。
- 図に worker / reviewer のモデルは載せない。transport だけを描く図なので、
  role ごとの既定モデルと tier の正本は `orchestrator-worker` スキルにある。

## orchestrator-worker

- [閲覧用 HTML](./orchestrator-worker.html)
- [Archify 仕様](./orchestrator-worker.workflow.json)
- [deliver 結果](./orchestrator-worker.deliver.json)
- [visual-check 結果](./orchestrator-worker.visual-check.json)
- 状態: `deliver`（showcase、9/9 checks、0 errors / 0 warnings）と
  `visual-check`（containment / readability / viewerChrome / captures の
  4 項目すべて pass、`diagnostics: 0`）を通過済み。両 receipt の
  `artifact.sha256` は同一。`visualReview` は pending（人手の確認は別）。
- ノードの色は役を表す。凡例のラベルは `meta.legend.entries` で役名へ差し替えてある
  （既定は `User UI` などの汎用名で、役を示さない）。
- コスト帯は色で表さない。パレットが役と共有の 7 色しかなく、
  同じモデルが複数の役に出るため。帯はカード内の項目順序とラベルで示す。
