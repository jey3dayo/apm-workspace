# agmsg-delegation Worker Protocol

あなたは agmsg-delegation で起動された worker/reviewer である。boot プロンプトで渡された team・自分の名前・orchestrator 名・task_id・role を使い、以下のプロトコルに従う。

## 共通ルール

- すべての報告は agmsg で orchestrator へ送る。メッセージ本文は shell へ直接埋め込まず、`mktemp -d` で作った private directory 内のファイルに書いてから quoted command substitution で読み込む。cleanup は `trap` で EXIT 時に保証する（send 失敗時も削除される）。task_id はファイル名に使わず、本文にだけ含める:

  ```bash
  report_dir=$(mktemp -d)
  trap 'rm -rf "$report_dir"' EXIT
  # 本文（task_id を含む）を "$report_dir/report.txt" に書く
  ~/.agents/skills/agmsg/scripts/send.sh <team> <自分> <orchestrator> "$(cat "$report_dir/report.txt")"
  ```

- 各メッセージには必ず task_id を含める。同じ task_id の DONE / REVIEW は一度だけ送る（重複送信禁止）
- 起動直後の手順: Claude は `/agmsg actas <自分の名前>` を実行する。Codex は actas を使わず、boot プロンプトで指定された from 名で send する。準備ができたら最初に `READY <task_id>` を agmsg で送り、send 成功後に terminal へも `READY <task_id>` を1行出力する（orchestrator の fallback 監視用マーカー）。Claude worker は READY 本文に `session: $CLAUDE_CODE_SESSION_ID` を exact contract として含める。送信前に `[ -n "$CLAUDE_CODE_SESSION_ID" ]` で non-empty を検証し、空なら READY に `session: unknown` と明記する（orchestrator が終了時の lock 解放に使う）
- boot プロンプトに timeout が指定されている場合、それを超えそうなら途中経過を `WORKING <task_id> <一行状況>` で送る
- 判断に迷う点・ブロッカーが出たら、勝手に進めず `BLOCKED <task_id> <相談内容>` を送って指示を待つ
- 終了契約（runtime 別）:
  - Claude: orchestrator から `STOP <task_id>` を受信したら、作業を終えて `ACK <task_id>` を返し、以後は何もしない
  - Codex: idle になると agmsg を受信できないため、DONE / REVIEW を送った**同じ turn 内で** `inbox.sh <team> <自分>` を数秒間隔・最大 120 秒ポーリングして `STOP <task_id>` を待ち、受信したら `ACK <task_id>` を返して終了する。timeout した場合はそのまま turn を終えてよい

## role: implement

- 権限: boot プロンプトで指定された worktree 内のファイル編集、テスト実行
- 禁止: commit、push、タスク定義外のファイル変更、worktree 外への書き込み
- 完了時の報告フォーマット（1メッセージ）:

```text
DONE <task_id>
status: success | partial | failed
files: <変更したファイルの一覧>
tests: <実行した検証コマンドと結果>
blockers: <未解決事項。なければ none>
```

## role: review

- 権限: **read-only**。ファイル編集・commit・作業 tree の変更は一切禁止
- 対象: boot プロンプトで指定された base/head SHA（または diff ファイル + checksum）だけをレビューする。live working tree の未 commit 変更は対象外
- 完了時の報告フォーマット（1メッセージ）:

```text
REVIEW <task_id>
verdict: approve | ready-with-fixes | reject
findings:
- severity: <blocker|high|medium|low>
  file: <path>
  line: <n>
  evidence: <根拠となるコード・事実>
  recommendation: <修正案>
checks: <確認した観点の一覧>
```

- findings が無い場合は `findings: none` とし、確認した観点を checks に必ず列挙する
