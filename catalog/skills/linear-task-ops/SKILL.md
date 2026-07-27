---
name: linear-task-ops
description: "JEY workspace 固有の Linear 運用ルール: issue のプロジェクト自動ルーティング、ラベル/タイトル/取引ログの書式、Asana からの移行マッピング、ガードレール。CRUD 自体は Linear MCP tools を使い、MCP が使えない環境や MCP に無い操作のみ GraphQL スクリプトへフォールバックする。Use when creating or editing Linear tasks, choosing a project or label, migrating task notes from Asana, or appending transaction logs (date/payment/price) to an existing issue."
---

# Linear Task Ops

## 役割分担

| 用途                                                         | 使うもの                                                                     |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| 読み取り（issue / project / label / state の照会・検索）     | Linear MCP tools（`list_issues`, `get_issue`, `list_projects` など）         |
| 書き込み（issue 作成・更新、コメント追加）                   | Linear MCP（`save_issue`, `save_comment`）+ 必ず再取得して検証。下記の注意点 |
| プロジェクト振り分け・ラベル・書式・運用ルール               | このスキル（以下のルール）                                                   |
| MCP に無い操作 / 書き込みが期待どおり反映されない / MCP なし | `scripts/linear_task.py`（GraphQL フォールバック）                           |

MCP が利用可能な場合は読み取りを自前スクリプトで再実装しない。逆に MCP を使う場合も、
プロジェクト選択・ラベル・タイトル・コメント書式はこのスキルのルールに従う。

### 書き込みの信頼性に関する注意

claude.ai / ChatGPT のアプリ側 Linear コネクタは、issue の作成・編集で
挙動が一致しない（同一の MCP だと想定していたが実際には差異がある）。
そのため書き込みは次の手順を守る。

1. 書き込みは APM 管理の `linear` MCP（`https://mcp.linear.app/mcp`）を優先する。
   アプリ側コネクタしか無い環境では、その差異を前提に扱う
2. `save_issue` / `save_comment` の直後に `get_issue` で対象フィールド
   （project / labels / state / dueDate / 本文）を再取得して照合する
3. 期待どおり反映されていないフィールドがあれば、そのフィールドだけ
   `scripts/linear_task.py` の GraphQL 経路で再実行する
4. 反映されなかった操作とフィールドをユーザーに報告する。黙って再試行を繰り返さない

## Project Routing

個人 workspace では team `JEY` に作成し、必ずプロジェクトへ振り分ける。
プロジェクト ID・一覧は `references/linear-projects-jey.md` を参照。

### 分類ルール

| プロジェクト | 対象ドメイン                                       | キーワード例                                                                                       |
| ------------ | -------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| finance      | 決済・サブスク・固定費・ポイ活・請求               | 支払い、請求、決済、サブスク、解約、ポイント、固定費、d払い、クレカ、引き落とし、ギフトコード      |
| household    | 家庭・生活基盤（住宅・保険・税・育児・光熱・車）   | 住宅、保険、確定申告、ふるさと納税、育児、保育園、光熱費、車検、通信契約                           |
| labs         | 個人学習・調査・技術検証・個人開発実験             | 調べる、検証、学習、試す、リサーチ、PoC、実験、ドキュメント読む                                    |
| GBF          | ゲーム、特にグランブルーファンタジー全般           | ゲーム、グラブル、GBF、古戦場、マグナ、召喚石、十天衆、エーテル                                    |
| workbench    | 会社雑務・その他個人タスク（上記に該当しないもの） | 申請、会議、雑務、確認、連絡、その他                                                               |
| リポジトリ名 | 特定リポジトリの開発タスク                         | `ultra-rss-reader`, `ca-connect-site`, `cygate`, `pr-labeler`, `LoCA` など repo 名が明示された場合 |

`finance` と `household` は重なりやすい。支出の発生・決済手段そのものが主題なら
`finance`、生活基盤の意思決定や手続きが主題なら `household`。

### 判断フロー

1. リポジトリ名が明示されている → 対応するプロジェクト
2. キーワードで明確に一致 → そのプロジェクト
3. 複数に該当 / 判断できない → 候補プロジェクト名を挙げてユーザーに確認
4. どれにも当てはまらない → workbench をデフォルトとして提案し確認

## ラベル

実在するラベルのみ使う。一覧は `references/linear-labels-jey.md`。
新しいタグを発明せず、既存の `term:*` / `risk:*` / `household:*` /
`Research` / `Bug` / `Improvement` / `Feature` から選ぶ。

- `risk:*` は P0–P3 と `unknown` の 5 値。issue ごとに 1 つだけ付け、
  既存の `risk:*` があれば置換する
- 判定できないものは `risk:unknown` を付け、着手前に P0–P3 へ確定させる
- 周期タスクには `term:*` を付ける

## タイトル・コメント書式

- `finance` のタイトル規約: `[領域] 何を直す/防ぐか（期待結果）`
- 取引ログは 1 行 1 レコードで集計しやすい形にする
  - `2026-03-14 | d払いタッチ | 4,435円`
- 本文中に散文で期限が書かれている場合は、issue の `dueDate` にも反映する

## Asana → Linear 移行フロー

1. 元タスクのデータ（title / notes / due date / status）を読む
2. 対象 issue を作成または特定する
3. `references/asana-to-linear-mapping.md` でフィールドを対応付ける
4. 支払いログは行単位レコードとして書く
5. 散文の期限は `dueDate` にも設定する

## GraphQL フォールバック

次のいずれかに該当する場合に `scripts/linear_task.py` を使う。

- Linear MCP が接続されていない環境（headless / cron / コネクタ未認証）
- MCP tool では実現できない操作がある
- issue の作成・編集で MCP 経由の書き込みが期待どおり反映されない
  （アプリ側コネクタの挙動差異。「書き込みの信頼性に関する注意」を参照）

```bash
export LINEAR_API_KEY=...   # または LINEAR_TOKEN / LINEAR_ENV_FILE=/path/to/.env
python3 scripts/linear_task.py teams
python3 scripts/linear_task.py states --team JEY
python3 scripts/linear_task.py list --team JEY --limit 30
python3 scripts/linear_task.py create --team JEY --project <PROJECT_ID> --title "..." --due-date 2026-03-31
python3 scripts/linear_task.py update --issue <ISSUE_ID> --team JEY --state "In Progress"
python3 scripts/linear_task.py comment --issue <ISSUE_ID> --body "2026-03-14 | d払いタッチ | 4,435円"
```

スクリプトで補った操作が MCP にも存在すると分かった場合は、MCP 側へ戻す。

## Guardrails

- 書き込み前に state 名を解決する。state 名はチームごとに異なる
- 小さな書き込みを繰り返さず、1 回の update / comment にまとめる
- API トークンをログやチャットに出さない
- 更新後は issue を再取得して結果を確認する。書き込み成功のレスポンスだけを
  根拠に完了を報告しない（コネクタによって反映されないフィールドがある）
