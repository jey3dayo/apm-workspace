# AWS Profiles

## 利用可能なProfile

### aws-caad-ndev-admin

- 用途: ニアショア向けアカウント
- 設定ファイルパス: `~/.config/perman-aws-vault/aws-caad-ndev-admin`
- リージョン: ap-northeast-1

### aws-caad-admin-role

- 用途: CAAD向けアカウント
- 設定ファイルパス: `~/.config/perman-aws-vault/aws-caad-admin-role`
- リージョン: ap-northeast-1

## AWS CLI統合設定

### credential_process の設定

`~/.aws/config` に以下の設定を追加:

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"

[profile aws-caad-admin-role]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role"
```

### credential_process とは

`credential_process` は、AWS CLIが認証情報を取得するために外部プログラムを実行する機能です。

#### メリット

- 一時的セキュリティ認証情報の自動取得
- 環境変数の手動設定が不要
- AWS CLIコマンド実行時に自動的に認証情報を更新

参考: [credential_process でAssumeRoleする | DevelopersIO](https://dev.classmethod.jp/articles/aws-cli-credential_process-assume-role/)

## 使用例

### AWS CLIでprofileを指定

```bash
# ニアショア環境のS3バケット一覧
aws s3 ls --profile aws-caad-ndev-admin

# CAAD環境のEC2インスタンス一覧
aws ec2 describe-instances --profile aws-caad-admin-role

# Lambda関数一覧
aws lambda list-functions --profile aws-caad-ndev-admin
```

### デフォルトprofileの設定

特定のprofileを頻繁に使用する場合、環境変数で設定:

```bash
# ニアショア環境をデフォルトに
export AWS_PROFILE=aws-caad-ndev-admin

# 以降、--profileオプション不要
aws s3 ls
aws ec2 describe-instances
```

### Terraformでの使用

```hcl
provider "aws" {
  profile = "aws-caad-ndev-admin"
  region  = "ap-northeast-1"
}
```

## Profile選択のガイドライン

### ビジネスユースケース別

| ユースケース               | 推奨Profile           |
| -------------------------- | --------------------- |
| ニアショア開発・テスト環境 | `aws-caad-ndev-admin` |
| CAAD向け本番環境           | `aws-caad-admin-role` |

### Claudeによる自動選択

Claudeがユーザーの要求から適切なprofileを選択する際の判断基準:

1. 明示的な指定: ユーザーが「ニアショア」「CAAD」などのキーワードを使用
2. 環境の推測: 「開発」「テスト」→ ndev、「本番」→ admin-role
3. デフォルト: 不明な場合は確認を求める

## セキュリティのベストプラクティス

1. 最小権限の原則: 必要な権限のみを持つprofileを使用
2. 一時的セキュリティ認証情報: perman-aws-vaultは一時的な認証情報のみを発行
3. 有効期限の管理: 認証情報の有効期限（Expiration）を把握
4. 定期的な監査: 使用しているprofileと権限を定期的に確認

## トラブルシューティング

### 認証情報が取得できない

```bash
# 手動で認証情報を確認
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin
```

有効期限が切れている場合は、`perman-aws-vault select`を再実行します。

### profileが見つからない

```bash
# 設定ファイルの確認
cat ~/.aws/config

# perman-aws-vault設定ファイルの確認
ls -la ~/.config/perman-aws-vault/
```

`~/.aws/config` が存在しない、または対象profileが未定義の場合は、`credential_process` を追加してください。必要に応じて `AWS_PROFILE` を設定すると `--profile` を省略できます。

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"
```

```bash
export AWS_PROFILE=aws-caad-ndev-admin
```
