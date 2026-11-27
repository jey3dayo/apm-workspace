---
name: chrome-devtools-profiles
description: chrome-devtools-mcp の製品別プロファイル（`$HOME/.cache/chrome-devtools-mcp/profiles/<product>`）を扱うときに使う。1Password 入りの `_template` からの新規プロファイル作成、ログイン済みプロファイルからのテンプレ作成、拡張の登録が消えたプロファイルの検証と復旧、プロファイルをコピー・移動した後の動作確認が対象。
---

# chrome-devtools-mcp プロファイルの作成・検証・復旧

製品別プロファイルは `$HOME/.cache/chrome-devtools-mcp/profiles/<product>`。`_template` は 1Password 拡張（`aeblfdkhhhdcdjpifhhbdiojplfjncoa`）入りのテンプレートで（導入時点の Web Store 版が入る。8.12.46.29 で検証）、新しい `<product>` はここからコピーして作る。

## 原則

Secure Preferences の `extensions.settings.<ID>` にある Web Store 拡張の登録は、Chrome 自身が書いたものだけが残る。検証した Chrome 158 では、157 時代の登録を `Secure Preferences` ごと復元しても（`protection` の有無によらず）、起動後に剥がされるか消える。Chrome 158 が初めて開いた時点で保護 prefs 全体がリセットされ、登録を作り直す必要があるため。157 時代に確認した「MCP 相当のフラグなら復元登録が保持される」は 158 では成り立たない（素のフラグでの挙動は 158 では未確認）。

登録は Chrome に導入させる（「拡張の再導入」）。Chrome が書いた登録は、完全な再起動を重ねても、別ディレクトリへ `rsync` したコピーでも保持される。起動を伴う確認は `verify-profile.sh` を通す。

## 境界

- 稼働中のプロファイルには触らない。3 つのスクリプトは `Singleton*` と `--user-data-dir=` を持つプロセスを見て中止する。`PROFILES_DIR` は末尾の `/` や `./` を正規化してから使う。
- 素のフラグで Chrome を起動しない。Chrome アプリ全体も終了しない（`pkill` / `killall` / `open -a` を使わない）。verify は自分が起動した PID だけを止める。
- `Local Extension Settings` の中身を読まない。復旧では対象プロファイル自身の拡張設定データ（`Local Extension Settings` / `Managed Extension Settings` / `IndexedDB` ほか）を保持する。
- `restore-extension.sh` は `Secure Preferences` をテンプレのものでファイルごと置き換える。Chrome 158 では復元した登録が起動後に剥がされるため、登録の復旧には使わない（「拡張の再導入」を使う）。対象にだけある他の拡張の登録は失われ、tracked prefs（起動ページ・ホーム・検索エンジンなど）もテンプレ側の値に戻る。元の `Secure Preferences` と `Preferences` は `$BACKUP_DIR` に残り、失敗時の巻き戻し対象になる。
- 対象に `Default/Extensions/<ID>` が既にあれば、`$BACKUP_DIR/<target>-<ts>/Extensions-<ID>/` へ退避してからテンプレの実体に差し替える。巻き戻しでは退避した実体を元の場所へ戻す。

## スクリプト

配布先は `$HOME/.agents/skills/chrome-devtools-profiles/scripts/`。環境変数 `PROFILES_DIR` / `BACKUP_DIR` / `CHROME_BIN` で場所を変えられる。

```bash
S="$HOME/.agents/skills/chrome-devtools-profiles/scripts"
"$S/create-template.sh" <source-profile> [template-name=_template]  # 許可リストのデータだけをコピーしてテンプレを作り、verify する
"$S/verify-profile.sh" <profile>                                    # MCP 相当フラグで 2 回起動し、登録・実体・exit_type を確認する
"$S/restore-extension.sh" <target-profile> [template-name=_template] # テンプレの拡張と Secure Preferences を戻す。Chrome 158 では登録が保持されない
"$S/reinstall-extension.py" <pre|edit|install|check> <profile>      # Chrome 自身に拡張を導入させる（下の手順）
```

`create-template.sh` は、残すものだけを `$PROFILES_DIR/.<template>.partial-<pid>` へコピーする許可リスト方式で、サイトデータを消す方式ではない。`Preferences` を整えて partial を verify し、通ったときだけ本名へ移す。失敗すると partial が一時名のまま残る。元プロファイル由来のデータを含むため、不要になったら削除する。

## 拡張の再導入（登録が stub になったプロファイル）

`reinstall-extension.py` の 4 段階を 1 プロファイルずつ、その製品の steward・worker の chrome-devtools セッションが止まっていることを確認して実行する。

1. `pre`: ベースライン（有効 cookie 数・`Login Data` の行数・拡張データの大きさ・他の登録・ホーム・検索）を記録し、`$BACKUP_DIR/<profile>-<ts>` へ全体をコピーし、直近の認証必須ページを通常設定で開く。
2. `edit`: `Secure Preferences` から 1Password の登録と `protection` を除き、`Default/Extensions/<ID>` を trash する。
3. `install`: `--apps-gallery-install-auto-confirm-for-tests=accept` 付きで `chrome-devtools-mcp` を `--userDataDir` 指定で起動し、Web Store ページの「Chrome に追加」をクリックする。導入には約 30 秒かかるので登録が完全になるまで待つ（短い待ちで閉じると導入されない）。
4. `check` を 2 回（そのたびに完全な再起動）: ベースラインとの比較、認証必須ページの再表示、拡張 popup が開くことを確認する。

進む条件: 登録が完全（`manifest`・`location` 1・`path`・`disable_reasons` が空）、`Login Data` の行数と他の登録が同じ、ホーム・検索が変わらない、拡張データのディレクトリが残る（LevelDB は compaction で縮むことがある）、認証必須ページがベースラインと同じ結果、popup が初回サインイン画面でない。満たさなければ次のプロファイルへ進まず、止めて報告する。

巻き戻し: Chrome と MCP が止まり `Singleton*` も無いことを確認できなければ復元しない。確認できたら変更後のプロファイルを `<profile>.failed-<ts>` として `$BACKUP_DIR` へ移し、`pre` のコピーを `cp -Rc` で戻し、サイズと登録状態が `pre` 時点と一致するか確認する。バックアップには Cookies と `Login Data` が入るため、全プロファイルでログインと autofill を確認するまで残し、確認後に trash する。

`_template` に適用したあとは、`rsync` した新規 `<product>` の登録もそのまま保持される。再導入は Store の最新版を入れる。Web Store ページのボタン文言とテストフラグに依存するため、Chrome か `chrome-devtools-mcp` の更新で止まったらこの節を見直す。

## 新規 `<product>` の作成

1. テンプレが未稼働であることを確認する。`_template/Singleton*` が無く、`--user-data-dir=` に `_template` を持つプロセスも無いこと。
2. `rsync -a --exclude='Singleton*' "$PROFILES_DIR/_template/" "$PROFILES_DIR/<product>/"`
3. `"$S/verify-profile.sh" <product>`

## 合格条件

- `verify-profile.sh`: 2 サイクルとも拡張の登録・`disable_reasons` が空（無い・`[]`・`0`）・`Extensions` 配下の実体と `manifest.json`・`exit_type` が OK で、最終行が `VERIFY OK <profile>`。
- `restore-extension.sh`: 最終行が `RESTORE OK <target>`。失敗時は `Secure Preferences` / `Preferences` と拡張の実体が巻き戻され、バックアップが残る。
- `create-template.sh`: verify が通り、最終行が `CREATE OK <template>`。

並列セッションでのプロファイル運用は `apm-usage` の `references/repo-local-mcp.md`「chrome-devtools Parallel Sessions」節を参照する。
