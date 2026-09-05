# 📚 AI agent 委譲フロー図

**最終更新**: 2026-09-05
**対象**: APM の AI agent 協働フローを後から確認する人
**タグ**: `category/architecture`, `audience/developer`, `tool/agmsg`

このディレクトリでは、AI agent の委譲・引き継ぎフローを Archify の仕様と閲覧用 HTML で保管する。

## すぐ見る

- [agmsg-delegation の確定版 HTML](./agmsg-delegation.html)
- [orchestrator-worker の候補仕様](./orchestrator-worker.workflow.json)

## agmsg-delegation

- [閲覧用 HTML](./agmsg-delegation.html)
- [Archify 仕様](./agmsg-delegation.workflow.json)
- 状態: Archify showcase の `deliver` と `visual-check` を通過済み。

## orchestrator-worker

- [候補仕様](./orchestrator-worker.workflow.json)
- 状態: showcase 検証で構図エラーが残ったため、HTML の `deliver` と `visual-check` は未実行。
- 現在の blocker: `steward-direct` と `verify-report` が 42px の corridor を共有。
- この JSON は候補の保管用。未検証の図を確定版として扱わない。
