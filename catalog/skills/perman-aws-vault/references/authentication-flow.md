# PERMAN Federation CIBA認証フロー

## 概要

perman-aws-vaultは、PERMAN FederationのCIBA (Client Initiated Backchannel Authentication) フローを利用してAWS一時的セキュリティ認証情報を取得します。

このドキュメントでは、認証の仕組み、実行手順、トラブルシューティング、セキュリティベストプラクティスを詳細に説明します。

## クイックスタート

### 認証情報取得

```bash
# ニアショア環境
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin

# CAAD環境
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role
```

### 認証状態確認

```bash
# 現在の認証状態を確認
aws sts get-caller-identity
```

正常時の出力例：

```json
{
  "UserId": "AIDACKCEVSQ6C2EXAMPLE",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

## 認証フロー

### 初回実行時の動作

#### 1. ブラウザ認証

コマンド実行時にブラウザが自動的に開きます：

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

#### 2. Authentication Message表示

認証メッセージが表示されます：

```
[perman-aws-vault] Please login to PERMAN Federation
Authentication Message: 573298
```

重要: この数字をWeb画面と照合してください（セキュリティ確認）

#### 3. 認証完了

ブラウザで認証完了後、JSON形式で一時認証情報が出力されます：

```json
{
  "Version": 1,
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "SessionToken": "...",
  "Expiration": "2025-10-09T14:13:48Z"
}
```

### キャッシュと有効期限

- キャッシュ機能: 認証情報は自動的にキャッシュされます
- 有効期限: `Expiration`フィールドに記載された時刻まで再利用可能
- 再認証: 有効期限切れ時は再度コマンドを実行して再認証してください

```bash
# キャッシュが有効な場合は即座に認証情報が返される
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin

# キャッシュ期限切れの場合は再度ブラウザ認証が必要
```

### 詳細な認証フロー（select コマンド）

#### 1. Service Providerの選択

```bash
perman-aws-vault select
```

コマンドを実行すると:

1. PERMAN Federationから認証を求めるメールが届く
2. webhook通知を設定している場合は、設定したURLにも通知される
3. CLIに認証メッセージが表示される

```
[perman-aws-vault] Please login to PERMAN Federation
Authentication Message: 611456
```

### 2. PERMAN Federationへのログイン

1. メールのリンクからPERMAN Federationにログイン
2. 認証メッセージの確認:
   - CLIに表示された認証メッセージ（例: 611456）
   - Web画面に表示される認証メッセージ
   - これらが一致することを必ず確認する（セキュリティ重要）

3. ユーザーコードを入力
4. 認証リクエストの許可

### 3. Service Providerの選択

認証が成功すると、利用可能なService Provider一覧が表示されます:

```
Select Service Provider
  aws-aitech-cabi
  aws-am-blog-tama
  aws-caad-admin-role
  aws-caad-ndev-admin
  aws-caproni
  idg-cagra-aws
  idg-cygate-aws

---------- Service Provider ----------
AccountName:    aws-aitech-cabi
Role:          adtech-aws-cabi-admin
Note:          adtech-aws-cabi-admin
```

選択したService Providerの設定ファイルが作成されます。

## 認証メッセージについて

### 重要性

認証メッセージは、認証リクエストが正当なものであることを確認するための重要な情報です。

#### 必ず確認すること

- CLIに表示された認証メッセージ
- PERMAN Federation Web画面に表示される認証メッセージ
- これらが**完全に一致する**ことを確認

### 確認例

#### CLI側

```bash
$ perman-aws-vault select
Authentication Message: 111111  👈 この数字を確認
```

#### Web側

PERMAN Federation画面に表示される認証メッセージと照合します。
（画像参照: auth-message-at-web.png）

## Webhook通知（任意設定）

PERMAN FederationのCIBAフローの認証リクエストは、デフォルトでは社用メールアドレスに通知されます。

オプションでwebhook通知を設定することも可能です。

設定手順: <https://docs.perman.jp/docs/profile/notification_setting/>

## コマンド実行時の認証

### exec コマンド

```bash
perman-aws-vault exec aws sts get-caller-identity
```

コマンド実行時にも認証メッセージが表示されます:

```
Authentication Message: XXXXXX
```

### print コマンド

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

認証情報をJSON形式で出力します:

```json
{
  "Version": 1,
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "SessionToken": "...",
  "Expiration": "2025-10-20T14:07:15Z"
}
```

## エラー対処法

### トークン期限切れエラー

```text
Error: ExpiredToken: The security token included in the request is expired
```

解決方法: Perman Federation認証コマンドを再実行

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

### 認証情報が見つからないエラー

```text
Error: Unable to locate credentials
```

#### 解決方法

1. Perman Federation認証が正しく実行されているか確認
2. 環境変数やプロファイル設定を確認

```bash
# 認証状態確認
aws sts get-caller-identity

# 認証が必要な場合
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

### ブラウザが開かない

症状: `perman-aws-vault print`実行時にブラウザが開かない

#### 解決方法

1. ブラウザが既定のアプリケーションとして設定されているか確認
2. 手動でPERMAN Federationにアクセスして認証
3. 環境変数`BROWSER`を設定

```bash
export BROWSER=/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

### 認証がループする

症状: 何度認証してもブラウザ認証画面が表示される

#### 解決方法

1. キャッシュファイルを削除

   ```bash
   rm -rf ~/.config/perman-aws-vault/cache
   ```

2. 再度認証を実行

### 権限エラー

症状: 認証は成功するが、AWS操作で権限エラーが発生

#### 解決方法

1. 正しいプロファイルを使用しているか確認
2. IAMロールの権限設定を確認
3. リソースのタグやポリシーを確認

```bash
# 現在のIAMロールを確認
aws sts get-caller-identity --query 'Arn'

# 期待されるARN形式
# arn:aws:sts::123456789012:assumed-role/project-name-*-role/...
```

## 環境別プロファイル

### プロファイル一覧

| プロファイル名        | 対象環境   | 用途                               | パス                                             |
| --------------------- | ---------- | ---------------------------------- | ------------------------------------------------ |
| `aws-caad-ndev-admin` | ニアショア | 開発・検証環境へのアクセス         | `~/.config/perman-aws-vault/aws-caad-ndev-admin` |
| `aws-caad-admin-role` | CAAD       | 本番・ステージング環境へのアクセス | `~/.config/perman-aws-vault/aws-caad-admin-role` |

### プロファイルの使い分け

```bash
# ニアショア環境での作業
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
aws s3 ls  # ニアショア環境のリソースにアクセス

# CAAD環境での作業
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role
aws s3 ls  # CAAD環境のリソースにアクセス
```

## mise を使った自動プロファイル適用

プロジェクトルートの `.env` ファイルに以下を追加することで、プロジェクトディレクトリで作業中は自動的に適切なプロファイルが使用されます：

```bash
# AWS Configuration
# Automatically apply AWS profile for this project
AWS_PROFILE=aws-caad-ndev-admin  # または aws-caad-admin-role
```

### 設定方法

1. プロジェクトルートに `.env` ファイルを作成または編集
2. 上記の設定を追加（プロファイル名は環境に応じて変更）
3. mise が自動的に環境変数を読み込みます

### 動作確認

```bash
# ディレクトリに移動すると自動的に環境変数が設定される
cd /path/to/project

# 環境変数が設定されているか確認
echo $AWS_PROFILE
# → aws-caad-ndev-admin（設定した値が表示される）

# 認証情報の確認（--profile オプション不要）
aws sts get-caller-identity
```

### メリット

- 🎯 **自動適用**: プロジェクトディレクトリに入ると自動的に適切なプロファイルが使用される
- ⚡ **効率化**: `--profile` オプションを毎回指定する必要がなくなる
- 🔒 **安全性**: `.env` は `.gitignore` 対象なので、個人設定として安全に管理できる
- 🤝 **チーム統一**: チーム全体で同じ設定パターンを共有可能

## セキュリティベストプラクティス

### 認証情報の取り扱い

- コマンド履歴: 認証情報は標準出力に表示されますが、シェル履歴には残りません
- 環境変数: 認証情報は一時的なセッショントークンであり、有効期限後は無効化されます
- 共有禁止: 認証情報を他のユーザーと共有しないでください

### トークンの有効期限管理

```bash
# 有効期限の確認
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin | jq '.Expiration'

# 出力例: "2025-10-09T14:13:48Z"
```

### 定期的な認証確認

長時間の作業時は、定期的に認証状態を確認することを推奨します。

```bash
# 作業前の確認
aws sts get-caller-identity

# AWS CLI/Terraformコマンド実行

# 作業後の確認（必要に応じて）
aws sts get-caller-identity
```

### 認証メッセージの照合（重要）

1. 認証メッセージの照合を必ず行う
   - CLIに表示される数字
   - Web画面に表示される数字
   - これらが完全に一致することを確認

2. ユーザーコードは安全に保管する
3. 一時的セキュリティ認証情報の有効期限を把握する
4. 不要になった連携アプリは解除する
