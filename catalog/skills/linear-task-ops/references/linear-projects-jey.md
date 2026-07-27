# Linear プロジェクト一覧（team: JEY / 取得日: 2026-07-27）

## プロジェクト

| プロジェクト名   | ID                                   | ステータス  | 用途                                     |
| ---------------- | ------------------------------------ | ----------- | ---------------------------------------- |
| finance          | af80afe7-be9f-47f9-a1b2-b2bbd3ed04f4 | In Progress | 支払い・決済・サブスク・固定費・ポイ活   |
| household        | e6a8c27b-ab0c-475c-a038-4d955b557ea4 | Backlog     | 家庭・生活基盤（住宅・保険・税・育児等） |
| labs             | d72d07ba-695c-471c-9a29-a8d975bc7976 | In Progress | 学習・調査・技術検証・研究               |
| GBF              | 108edeba-9579-41fb-8b32-82d44678d382 | In Progress | グランブルーファンタジー全般             |
| workbench        | 039463de-1a52-4ce7-a89b-c3d3cd26bb96 | In Progress | 会社雑務・その他個人タスク               |
| LoCA             | c95a2787-7dd8-4fe8-9aac-ffb1ae534b71 | Backlog     | -                                        |
| ultra-rss-reader | 530ead2d-64f7-42a3-92c4-c4f248b2ff90 | Backlog     | repo: jey3dayo/ultra-rss-reader          |
| ca-connect-site  | 143b6a46-2d79-475b-83a4-68dd6c121d17 | Backlog     | -                                        |
| cygate           | 05fed0ff-02a4-4934-b340-9340d84541e1 | Backlog     | -                                        |
| pr-labeler       | ce1a8d5f-e5c3-4f5d-8dd2-d293ee135734 | Backlog     | -                                        |

`finance` は旧 `finance-ops`。改名のみで ID は同じ。

## 使い方

MCP はプロジェクト名で指定できる。

```text
save_issue(team: "JEY", project: "finance", title: "...")
```

GraphQL フォールバック（`scripts/linear_task.py`）では ID を渡す。

```bash
python3 scripts/linear_task.py create \
  --team JEY \
  --project af80afe7-be9f-47f9-a1b2-b2bbd3ed04f4 \
  --title "タスクタイトル"
```

## 注意

- 追加・削除・改名があった場合は Linear MCP の `list_projects`（`team: JEY`）で
  再取得してこのファイルを更新する。
- 分類ルールは `SKILL.md` の「Project Routing」セクションを参照。
