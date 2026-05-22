# perman-aws-vault 高度な使い方

## Policyの指定

`AssumeRoleWithSAML` の `Policy` と `PrincipalArn` に対応したパラメータを設定ファイルで指定できます。

### 設定例

設定ファイル（例: `~/.config/perman-aws-vault/aws-caad-ndev-admin`）に以下のように記述:

```yaml
spID: 0000000000
policy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"},{"Effect":"Deny","Action":"iam:*","Resource":"*"}]}'
arns:
  - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### パラメータ説明

#### spID

- Service Provider ID
- PERMAN Federationで管理されているService Providerの識別子

#### policy

- インラインポリシー（JSON形式の文字列）
- セッションに適用される権限ポリシー
- `AssumeRoleWithSAML` の `Policy` パラメータに対応

#### arns

- 管理ポリシーのARNリスト
- `AssumeRoleWithSAML` の `PrincipalArn` パラメータに対応
- 複数のARNを指定可能

### ユースケース

#### 1. 権限を制限したセッション

IAM権限を除外してS3のみ操作可能にする:

```yaml
spID: 0000000000
policy: '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"s3:*","Resource":"*"},{"Effect":"Deny","Action":"iam:*","Resource":"*"}]}'
```

#### 2. 読み取り専用アクセス

S3への読み取り専用アクセス:

```yaml
spID: 0000000000
arns:
  - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

#### 3. 複数のマネージドポリシー

複数のAWSマネージドポリシーを組み合わせ:

```yaml
spID: 0000000000
arns:
  - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
  - arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
  - arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess
```

## 設定ファイルの場所

### デフォルトの読み込み順序

perman-aws-vaultは以下の順序で設定ファイルを探索:

1. カレントディレクトリ
2. 親ディレクトリ（上位階層へ再帰的に探索）
3. `~/.config/perman-aws-vault/`

### プロジェクト固有の設定

プロジェクトごとに異なる権限が必要な場合、プロジェクトディレクトリに設定ファイルを配置:

```
project/
├── .perman-aws-vault/
│   └── config.yaml
└── terraform/
    └── main.tf
```

この場合、`project/` ディレクトリで `perman-aws-vault exec` を実行すると、プロジェクト固有の設定が使用されます。

## execコマンドの詳細

### 基本的な使い方

```bash
perman-aws-vault exec <command> [args...]
```

### 環境変数への展開

`exec` コマンドは、取得した一時的セキュリティ認証情報を以下の環境変数に設定してコマンドを実行:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### 使用例

#### AWS CLI

```bash
perman-aws-vault exec aws s3 ls
perman-aws-vault exec aws ec2 describe-instances
```

#### Terraform

```bash
perman-aws-vault exec terraform plan
perman-aws-vault exec terraform apply
```

#### カスタムスクリプト

```bash
perman-aws-vault exec ./deploy.sh
perman-aws-vault exec python manage_aws_resources.py
```

## printコマンドの詳細

### 基本的な使い方

```bash
perman-aws-vault print [-p <path>]
```

### オプション

- `-p, --path`: 設定ファイルのパス（ファイル名は不要、ディレクトリパスのみ指定）

### 出力形式

JSON形式で認証情報を出力（`credential_process` と互換性あり）:

```json
{
  "Version": 1,
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "SessionToken": "...",
  "Expiration": "2025-10-20T14:07:15Z"
}
```

### 使用例

#### 手動で環境変数に設定

```bash
# 認証情報を取得
creds=$(perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin)

# 環境変数に設定
export AWS_ACCESS_KEY_ID=$(echo $creds | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $creds | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $creds | jq -r '.SessionToken')

# AWS CLIコマンド実行
aws s3 ls
```

#### 有効期限の確認

```bash
perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin | jq -r '.Expiration'
```

## ベストプラクティス

### 1. 設定ファイルの管理

- プロジェクトルートに `.perman-aws-vault/` ディレクトリを作成
- `.gitignore` に追加（認証情報を含むため）
- チーム内で設定テンプレートを共有

### 2. 権限の最小化

- 必要最小限のポリシーのみを適用
- インラインポリシーで明示的にDenyを設定
- 期間限定の認証情報を活用

### 3. セキュリティ

- 認証メッセージを必ず確認
- ユーザーコードを安全に保管
- 定期的に連携アプリを見直し
- 不要になったセッションは早めに破棄

### 4. 開発効率

- `credential_process` を活用して認証を自動化
- プロジェクトごとに適切な権限を設定
- スクリプトやCI/CDパイプラインに統合
