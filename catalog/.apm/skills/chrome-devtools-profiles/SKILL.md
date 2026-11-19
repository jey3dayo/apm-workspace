---
name: chrome-devtools-profiles
description: chrome-devtools-mcp の製品別プロファイル（`$HOME/.cache/chrome-devtools-mcp/profiles/<product>`）を扱うときに使う。1Password 入りの `_template` からの新規プロファイル作成、ログイン済みプロファイルからのテンプレ作成、拡張の登録が消えたプロファイルの検証と復旧、プロファイルをコピー・移動した後の動作確認が対象。
---

# chrome-devtools-mcp プロファイルの作成・検証・復旧

製品別プロファイルは `$HOME/.cache/chrome-devtools-mcp/profiles/<product>`。`_template` は 1Password 拡張（`aeblfdkhhhdcdjpifhhbdiojplfjncoa`、検証済みの版 8.12.46.29）入りのテンプレートで、新しい `<product>` はここからコピーして作る。

## 原則

Secure Preferences の `extensions.settings.<ID>` にある Web Store 拡張の登録は、起動フラグに依存する。素のフラグ（実 keychain）で起動すると、登録は起動直後に stub 化して拡張が使えなくなる。MCP 相当のフラグ（`--use-mock-keychain --password-store=basic --disable-sync --enable-automation` など）で起動すれば、ファイルコピーしたプロファイルでも登録が保持される。そのため、起動を伴う確認はすべて `verify-profile.sh` を通す。

## 境界

- 稼働中のプロファイルには触らない。3 つのスクリプトは `Singleton*` と `--user-data-dir=` を持つプロセスを見て中止する。
- 素のフラグで Chrome を起動しない。Chrome アプリ全体も終了しない（`pkill` / `killall` / `open -a` を使わない）。verify は自分が起動した PID だけを止める。
- `Local Extension Settings` の中身を読まない。復旧では対象プロファイル自身の拡張設定データ（`Local Extension Settings` / `Managed Extension Settings` / `IndexedDB` ほか）を保持する。
- `restore-extension.sh` は `Secure Preferences` をテンプレのものでファイルごと置き換える。対象にだけある他の拡張の登録は失われる（元のファイルは `$BACKUP_DIR` に残る）。

## スクリプト

配布先は `$HOME/.agents/skills/chrome-devtools-profiles/scripts/`。環境変数 `PROFILES_DIR` / `BACKUP_DIR` / `CHROME_BIN` で場所を変えられる。

```bash
S="$HOME/.agents/skills/chrome-devtools-profiles/scripts"
"$S/create-template.sh" <source-profile> [template-name=_template]  # ログイン済みプロファイルからサイトデータを除いたテンプレを作り、verify する
"$S/verify-profile.sh" <profile>                                    # MCP 相当フラグで 2 回起動し、登録・実体・exit_type を確認する
"$S/restore-extension.sh" <target-profile> [template-name=_template] # テンプレの拡張と Secure Preferences を戻す。バックアップは $BACKUP_DIR
```

## 合格条件

- `verify-profile.sh`: 2 サイクルとも拡張の登録・`Extensions` 配下の実体・`exit_type` が OK で、最終行が `VERIFY OK <profile>`。
- `restore-extension.sh`: 最終行が `RESTORE OK <target>`。失敗時は Secure Preferences と復旧した拡張が巻き戻され、バックアップが残る。
- `create-template.sh`: verify が通り、最終行が `CREATE OK <template>`。

並列セッションでのプロファイル運用は `apm-usage` の `references/repo-local-mcp.md`「chrome-devtools Parallel Sessions」節を参照する。
