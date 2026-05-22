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

### CA-Nic-prd

- 用途: CA-Nic-prd の開発者用ロール
- PERMANロール表示: `aws-ca-nic-prd-developer`
- 設定ファイルパス: `~/.config/perman-aws-vault/CA-Nic-prd`
- リージョン: ap-northeast-1

## AWS CLI統合設定

### AWS_PROFILE discovery first

AWS_PROFILE は環境名から推測せず、実行対象のリポジトリや shell から発見してください。探索対象:

- ユーザー依頼やコマンド断片に明示された `AWS_PROFILE=<value>`
- 現在の shell の `AWS_PROFILE`
- `.env`、`.env.*`、`.envrc`
- `mise.toml`、`mise.local.toml`
- Terraform/CDK 実行ディレクトリの env 定義

`rg` で `AWS_PROFILE` だけを検索し、`.env` 全体を表示しないでください。AWS access key、secret key、session token は表示しません。

以下の場合は停止します:

- AWS_PROFILE が見つからない
- 複数の異なる AWS_PROFILE が見つかり、実行対象から一意に決まらない
- `AWS_PROFILE=encrypted:...` のような汚染値、空値、テンプレート値しかない
- `production`、`staging`、`CAAD` などの環境語だけで profile 名がない

### credential_process の設定

`~/.aws/config` に以下の設定を追加:

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"

[profile aws-caad-admin-role]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-admin-role"

[profile CA-Nic-prd]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/CA-Nic-prd"
```

### `~/.aws/config` の初期化方針

このスキルは、既知の perman-aws-vault profile については `~/.aws/config` の安全な初期化まで責務に含めます。

自動で実施してよいこと:

1. `~/.aws/` が無ければ作成する
2. `~/.aws/config` が無ければ作成する
3. 既知 profile が未定義なら profile stanza を追記する
4. 既存の profile、コメント、手動設定は保持する

自動で実施しないこと:

- 未知 profile 名の推測
- 既存 profile の競合する `credential_process` の上書き
- `~/.aws/credentials` への静的認証情報の書き込み
- secret 値の表示や保存

既存 profile があるが `credential_process` が違う場合は、AWS CLI 実行前に停止して確認してください。

profile の初期化または競合解消後の既定確認コマンド。AWS CLI の read-only inspection では `--profile` を使えます:

```bash
env -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  -u AWS_PROFILE \
  -u AWS_REGION \
  aws sts get-caller-identity --profile <profile-name> --region ap-northeast-1
```

AWS CLI の実体は `command -v aws` で確認してください。`/usr/local/bin/aws` のような絶対パスは、その環境で存在確認済みかつ通常の `aws` shim が汚染・故障している場合だけ使います。

Terraform/CDK では実行時と同じ profile 注入方法で検証してください:

```bash
env -u AWS_ACCESS_KEY_ID \
  -u AWS_SECRET_ACCESS_KEY \
  -u AWS_SESSION_TOKEN \
  AWS_PROFILE=<profile-name> \
  AWS_REGION=ap-northeast-1 \
  terraform plan
```

dotenvx や mise により `AWS_PROFILE=encrypted:...` / `AWS_REGION=encrypted:...` が入っている場合は、その値を profile 確定には使わず停止してください。`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`、`AWS_SESSION_TOKEN` が残っている場合は `AWS_PROFILE` より優先されるため、command-scoped `env -u` で外します。

`perman-aws-vault` の実体も先に探してください。Codex は通常作業で install しません。`command -v perman-aws-vault`、`mise which perman-aws-vault`、`/opt/homebrew/bin/perman-aws-vault`、`/usr/local/bin/perman-aws-vault`、`~/.mise/shims/perman-aws-vault` を確認し、見つからなければ停止します。

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
# 発見済み profile でのS3バケット一覧
aws s3 ls --profile <discovered-profile>

# 認証先確認
aws sts get-caller-identity --profile <discovered-profile> --region ap-northeast-1
```

### デフォルトprofileの設定

Terraform/CDK など `AWS_PROFILE` を読むツールでは、発見済み profile を環境変数で設定:

```bash
export AWS_PROFILE=<discovered-profile>

# 以降、--profileオプション不要
aws s3 ls
aws ec2 describe-instances
```

### Terraformでの使用

Terraform では、repo が定義する AWS_PROFILE を source of truth として扱います。provider に `profile = ...` を追加して回避するのではなく、`.env*`、`mise.toml`、shell、Terraform 実行ディレクトリから AWS_PROFILE を確定してから実行します。

```bash
AWS_PROFILE=<discovered-profile> terraform plan
```

## Profile選択のガイドライン

### ビジネスユースケース別

この表は候補を理解するための補助情報です。AWS_PROFILE が発見できない場合に、この表だけで profile を選んではいけません。

| ユースケース               | 推奨Profile           |
| -------------------------- | --------------------- |
| ニアショア開発・テスト環境 | `aws-caad-ndev-admin` |
| CAAD向け本番環境           | `aws-caad-admin-role` |
| CA-Nic-prd 開発者用ロール  | `CA-Nic-prd`          |

### AWS_PROFILE discovery first

Claude/Codex が profile を決める際の判断基準:

1. AWS_PROFILE をリポジトリまたは現在の shell から発見する
2. 発見した AWS_PROFILE と `~/.aws/config` / `~/.config/perman-aws-vault/<profile>` の対応を確認する
3. `perman-aws-vault print -p <config-path>` を先に試す
4. profile が不明または複数候補なら停止する

「ニアショア」「CAAD」「CA-Nic」「production」などのキーワードは補助情報であり、AWS_PROFILE の代替にはしません。

## セキュリティのベストプラクティス

1. 最小権限の原則: 必要な権限のみを持つprofileを使用
2. 一時的セキュリティ認証情報: perman-aws-vaultは一時的な認証情報のみを発行
3. 有効期限の管理: 認証情報の有効期限（Expiration）を把握
4. 定期的な監査: 使用しているprofileと権限を定期的に確認

## トラブルシューティング

### 認証情報が取得できない

```bash
# 手動で認証情報を確認
perman-aws-vault print -p ~/.config/perman-aws-vault/<discovered-profile>
```

まず `print -p` を実行します。有効期限切れや未認証が確認できた場合だけ、`perman-aws-vault select` に進みます。

### profileが見つからない

```bash
# profile候補の確認
rg -n "AWS_PROFILE" .env* mise.toml mise.local.toml

# 実行ファイルの確認
command -v perman-aws-vault
mise which perman-aws-vault
```

AWS_PROFILE が特定できない場合は停止してください。`production` や `CAAD` という語だけで profile を推測しません。

`~/.aws/config` が存在しない、または発見済みの既知 profile が未定義の場合は、`credential_process` を初期化してください。必要に応じて `AWS_PROFILE` を設定すると `--profile` を省略できます。

```ini
[profile aws-caad-ndev-admin]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/aws-caad-ndev-admin"

[profile CA-Nic-prd]
region = ap-northeast-1
credential_process = sh -c "perman-aws-vault print -p ~/.config/perman-aws-vault/CA-Nic-prd"
```

```bash
export AWS_PROFILE=<discovered-profile>
```

### `perman-aws-vault select` の生成ファイル

`perman-aws-vault select` は、選択した Service Provider の `spID` をカレントディレクトリの `.perman-aws-vault` に書き込みます。`credential_process` で profile ごとに使う場合は、生成されたファイルを対象 profile の設定ディレクトリへ配置してください。

```bash
mkdir -p ~/.config/perman-aws-vault/CA-Nic-prd
cp .perman-aws-vault ~/.config/perman-aws-vault/CA-Nic-prd/.perman-aws-vault
rm .perman-aws-vault
```

このファイルは Service Provider ID の設定であり、AWS credential ではありません。

### MaxSessionDuration エラー

以下のエラーは、PERMAN Federation から返された `session_duration` が IAM role の MaxSessionDuration を超えている状態です。

```text
ValidationError: The requested DurationSeconds exceeds the MaxSessionDuration set for this role.
```

perman-aws-vault は PERMAN の SAML レスポンス内 `session_duration` を `AssumeRoleWithSAML` に渡します。ローカルの `.perman-aws-vault` に `duration_seconds` などを追加しても短縮できません。PERMAN Service Provider 側のセッション時間、または IAM role の MaxSessionDuration を合わせてください。
