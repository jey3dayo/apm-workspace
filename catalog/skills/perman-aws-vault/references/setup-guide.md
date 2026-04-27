# perman-aws-vault セットアップガイド

## 初期設定

### 1. ツールのインストール

#### Mac

```bash
brew tap PERMAN/tap git@github.com:PERMAN/homebrew-tap.git
brew install perman-aws-vault
```

#### Windows

```bash
scoop bucket add perman https://github.com/PERMAN/scoop-bucket.git
scoop install perman-aws-vault
```

#### 直接ダウンロード

リポジトリにアクセスできない場合:

```
https://cli.perman.jp/aws-vault/{version}/perman-aws-vault_{version}_darwin_amd64.tar.gz
https://cli.perman.jp/aws-vault/{version}/perman-aws-vault_{version}_darwin_arm64.tar.gz
https://cli.perman.jp/aws-vault/{version}/perman-aws-vault_{version}_windows_386.zip
https://cli.perman.jp/aws-vault/{version}/perman-aws-vault_{version}_windows_amd64.zip
https://cli.perman.jp/aws-vault/{version}/perman-aws-vault_{version}_windows_arm64.zip
```

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
5. `perman-aws-vault select`などのコマンドを実行
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
