# perman-aws-vault セットアップガイド

## 初期設定

### 1. ツールの確認

通常の Codex 作業では、perman-aws-vault をインストールしません。まず既存の実行ファイルを探し、見つからなければ停止して、探索した場所を報告してください。

```bash
command -v perman-aws-vault
mise which perman-aws-vault
```

追加で以下の候補を確認します:

- `/opt/homebrew/bin/perman-aws-vault`
- `/usr/local/bin/perman-aws-vault`
- `~/.mise/shims/perman-aws-vault`

見つからない場合は、`brew install` や `scoop install` に進まず停止します。インストール方法はユーザーまたは環境管理者が判断します。

### 2. ユーザー認証情報の設定

```bash
perman-aws-vault init
```

プロンプトに従って入力:

- PERMAN USER NAME: PERMANのユーザー名
- PERMAN User Code: 任意の値（PERMANのパスワードではありません）

## ユーザーコードについて

### ユーザーコードとは

ユーザーコードは、認証デバイスに認証リクエストの送信を許可するための秘密情報です。

#### 重要

- PERMAN Federationへの初回ログイン時に認証リクエストの許可を行うため、ユーザーコードを入力する必要があります
- ユーザーコードの値を変更すると、認証リクエストが送信されなくなります

### ユーザーコードを忘れた場合の対処法

1. PERMAN Federationへログイン
2. サイドメニューの「連携済みアプリ」をクリック
3. サービス名「PERMAN Federation」を連携解除
4. `perman-aws-vault init`を再実行し、ユーザーコードを再設定
5. まず `perman-aws-vault print -p <config-path>` を実行し、必要な場合だけ `perman-aws-vault select` を実行
6. 認証リクエストの許可時に**新しく設定したユーザーコード**を入力

## トラブルシューティング

### Windows環境での表示問題

WindowsのコマンドプロンプトやPowershellでANSIエスケープシーケンスが正しく表示されない場合:

```cmd
reg add HKEY_CURRENT_USER\Console /v VirtualTerminalLevel /t REG_DWORD /d 1
```

### 設定ファイルの読み込み

設定ファイルの読み込みは:

1. まずカレントディレクトリを参照
2. ファイルが存在しない場合は上位のディレクトリを参照
