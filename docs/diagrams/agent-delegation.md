# 📚 AI agent 委譲フロー図

**最終更新**: 2026-09-07
**対象**: APM の AI agent 協働フローを後から確認する人
**タグ**: `category/architecture`, `audience/developer`

このディレクトリでは、AI agent の委譲・引き継ぎフローを Archify の仕様と閲覧用 HTML で保管する。

## すぐ見る

- [orchestrator-worker の閲覧用 HTML](./orchestrator-worker.html)

agmsg-delegation の図（閲覧用 HTML と Archify 仕様）は、agmsg 依存の撤去（#150）でスキルごと削除した。履歴は git に残る。

## orchestrator-worker

- [閲覧用 HTML](./orchestrator-worker.html)
- [Archify 仕様](./orchestrator-worker.workflow.json)
- 状態: 2026-09-07 に `deliver`（showcase）と `visual-check` を通過済み。
  receipt と確認用スクリーンショットは 2026-11-03 にリポジトリから外した（git 履歴に残る）。
- ノードの色は役を表す。凡例のラベルは `meta.legend.entries` で役名へ差し替えてある
  （既定は `User UI` などの汎用名で、役を示さない）。
- コスト帯は色で表さない。パレットが役と共有の 7 色しかなく、
  同じモデルが複数の役に出るため。帯はカード内の項目順序とラベルで示す。
