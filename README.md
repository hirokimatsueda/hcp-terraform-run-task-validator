# HCP terraform Run Task Validator

このリポジトリは、HCP Terraform Run Task のインフラストラクチャを管理します。

AWS Lambda を使用して Run Task を実装し、Terraform の実行計画を検証します。

Run Task では HMAC 認証を実施します。

## アーキテクチャ概要

このプロジェクトは以下の 2 つの主要コンポーネントで構成されています：

1. Run Task 実行基盤（examples/01_run_task_resources）

   - Lambda 関数（検証ロジック）
   - Lambda Function URL
   - Parameter Store（シークレット管理）

2. Run Task 設定（examples/02_workspace_config）
   - Workspace 設定
   - Run Tasks 設定
   - HMAC 認証設定

## 前提条件

### AWS

- AWS OIDC 認証基盤が構築済みであること
  - [Dynamic Provider Credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration)に従って構築
  - IAM ロール ARN が利用可能であること

### HCP Terraform

- 組織が作成済みであること
- プロジェクトが作成済みであること
- Dynamic Provider Credentials が設定済みであること
  - 変数セット"aws-authentication"が作成済み
  - 必要な環境変数が設定済み
    - TFC_AWS_PROVIDER_AUTH
    - TFC_AWS_RUN_ROLE_ARN

## デプロイ手順

### 1. Run Task 実行基盤のデプロイ

1. Workspace の準備（手動）

   - 新しい Workspace を作成
     - 名前: `run-task-resources`
     - VCS 連携を設定
     - 作業ディレクトリ: `examples/01_run_task_resources`

2. Workspace に変数を設定

```
# カテゴリ: terraform
aws_region  = "ap-northeast-1"
environment = "production"
```

3. デプロイの実行

   - HCP Terraform UI からプランを実行
   - リソースを確認して適用

4. Remote state sharing の設定
   - `run-task-config` ワークスペース作成後に実施
   1. `run-task-resources` Workspace の設定画面を開く
   2. "Remote state sharing" セクションに移動
   3. "Share with specific workspaces" を選択
   4. `run-task-config` ワークスペースを追加

### 2. Run Task の設定

1. Workspace の準備（手動）

   - 新しい Workspace を作成
     - 名前: `run-task-config`
     - VCS 連携を設定
     - 作業ディレクトリ: `examples/02_workspace_config`

2. Workspace に変数を設定

```
# カテゴリ: terraform
tfc_organization_name           = "your-org-name"
tfc_project_name                = "your-project-name"
workspace_name                  = "your-workspace-name"
working_directory               = "your-working-directory"
vcs_repo_identifier             = "org/repo"
vcs_branch                      = "main"
github_username_or_organization = "your-github-username-or-organization"
run_task_workspace_name         = "run-task-resources"  # 手順1で作成したWorkspace名

# カテゴリ: env
TFE_TOKEN = "tfe-personal-token"
```

3. デプロイの実行
   - HCP Terraform UI からプランを実行
   - リソースを確認して適用

## セキュリティ考慮事項

### シークレット管理

- HMAC シークレットキーは Parameter Store で管理
- HCP Terraform API トークンは Parameter Store で管理
- Lambda Extension による Parameter Store 連携

### Run Task

- HMAC 認証による通信の保護
- Lambda Function URL の CORS 設定
- シークレットのキャッシュ管理

## 依存関係

- Terraform >= 1.10.3
- AWS Provider >= 5.0
- TFE Provider >= 0.61.0
- Python >= 3.13
- AWS Lambda Extension for Parameter Store

## カスタマイズ

Lambda 関数の検証ロジックは `examples/01_run_task_resources/lambda/main.py` で仮実装されています。

必要に応じて、以下のような検証を追加できます：

- 特定のリソースタイプの制限
- コスト見積もりの上限チェック
- セキュリティ要件の検証
- タグ付けルールの確認
