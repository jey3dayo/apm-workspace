# herdr の既存 workspace へ外部から対話 Claude を起動した実例

herdr の外にいる Claude セッションが、公開 CLI だけで既存 workspace に pane を足し、対話 Claude を起動した手順の記録です。確認した環境は macOS、herdr 0.9.5、2026-11-07 です。

## 位置づけ

この手順は、ユーザーが個別の操作として明示的に指定したときの実例です。agent への一般的な許可ではありません。

`catalog/skills/herdr/SKILL.md` は、agent が `HERDR_ENV=1` の pane の中だけから操作すると定めています。herdr 公式の agent skill も `HERDR_ENV=1` を既定の前提にしています。今回もこの既定は変えていません。次の点で、既定と区別して読んでください。

| 項目                                              | 既定                       | この実例                                |
| ------------------------------------------------- | -------------------------- | --------------------------------------- |
| 操作する agent の居場所                           | `HERDR_ENV=1` の pane の中 | herdr の外                              |
| 操作の根拠                                        | 既定の前提                 | ユーザーが個別に指定した操作            |
| 操作の範囲                                        | skill が定める範囲         | 下の手順に書いた公開 CLI の呼び出しだけ |
| `HERDR_ENV` の設定、socket の直接操作、権限の迂回 | 行わない                   | 行っていない                            |

別の場面で同じ操作をするときも、ユーザーがその操作を指定したかどうかを毎回確かめます。この文書を根拠に、確認なしで実行しません。

## 手順

`<workspace>` は既存 workspace の ID、`<pane>` はその中の既存 pane の ID、`<dir>` は作業ディレクトリ、`<new-pane>` は 2 の返り値です。

1. 構文と対象を確認します。入力はまだ送りません。

   ```sh
   herdr --help
   herdr pane --help
   herdr workspace list
   herdr pane list --workspace <workspace>
   herdr pane process-info --pane <pane>
   herdr pane read <pane> --source recent-unwrapped --lines 35
   ```

   `workspace list` で目的の workspace の label と ID を確認します。既存の pane は読むだけにして、入力を送りません。元の Claude セッションを保つためです。

2. 同じ workspace の中に pane を分割します。新しい workspace は作りません。

   ```sh
   herdr pane split --pane <pane> --direction right --cwd <dir> --no-focus
   ```

   返り値の `pane_id` を `<new-pane>` とし、`tab_id` が元の pane と同じ tab であることを確かめます。`--no-focus` は、人が見ている画面のフォーカスを奪わないためです。

3. シェルが入力を待っていることを確かめます。

   ```sh
   herdr pane process-info --pane <new-pane>
   herdr pane read <new-pane> --source visible --lines 12
   ```

   `foreground_process_group_id` が `shell_pid` と一致し、画面にプロンプトが出ていれば、入力待ちです。

4. Claude を起動します。起動時の指示は、保存したファイルを読ませるだけにします。

   ```sh
   herdr pane run <new-pane> "claude 'Read <brief-file> and continue the requested work interactively.'"
   ```

   モードや権限のフラグは渡しません。引数は通常の `claude` とファイル読込の指示だけです。

5. 起動を読み戻して確かめます。

   ```sh
   herdr pane process-info --pane <new-pane>
   herdr pane read <new-pane> --source recent-unwrapped --lines 28
   ```

   `process-info` の cwd が `<dir>` で、argv が手順 4 の引数と一致することを確かめます。画面に入力欄が出ていることも見ます。

## 起動後の扱い

- 起動後の Claude は、通常の対話セッションです。承認 UI への入力は、起動した側が代行せず、ユーザーが行います。
- 画面に auto mode が表示されることがあります。今回は既存の設定によるもので、起動した側からは切り替えていません。
- 指示ファイルには、作業の参照先、承認が要る操作、触らないものを書きます。今回の指示ファイルでは、実環境への移動、merge、deploy、install、削除を未承認と明記しました。
- 指示ファイルはリポジトリの外に置きます。

## 確認の限界

- 動作は herdr 0.9.5 の公開 CLI だけで確かめました。他の版では、サブコマンドやフラグを `--help` で確かめ直してください。
- 手順の中で agent の状態を待つ操作は使っていません。`pane read` で画面を読んで判断しています。
