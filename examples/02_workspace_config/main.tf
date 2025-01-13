terraform {
  required_version = "~> 1.10.3"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.62"
    }
  }

  cloud {
    workspaces {
      name = "run-task-config"
    }
  }
}

# 01_run_task_resourcesのステートを参照
data "terraform_remote_state" "run_task" {
  backend = "remote"

  config = {
    organization = var.tfc_organization_name
    workspaces = {
      name = var.run_task_workspace_name
    }
  }
}

# 既存のプロジェクトを参照
data "tfe_project" "example" {
  name         = var.tfc_project_name
  organization = var.tfc_organization_name
}

data "tfe_github_app_installation" "this" {
  name = var.github_username_or_organization
}

# Workspace作成
resource "tfe_workspace" "example" {
  name         = var.workspace_name
  organization = var.tfc_organization_name
  project_id   = data.tfe_project.example.id

  working_directory = var.working_directory

  # VCS設定
  vcs_repo {
    identifier                 = var.vcs_repo_identifier
    branch                     = var.vcs_branch
    github_app_installation_id = data.tfe_github_app_installation.this.id
  }
}

# Run Task設定
resource "tfe_organization_run_task" "validator" {
  organization = var.tfc_organization_name
  url          = data.terraform_remote_state.run_task.outputs.function_url
  name         = "terraform-validator"
  enabled      = true
  hmac_key     = data.terraform_remote_state.run_task.outputs.hmac_secret_key
}

# WorkspaceへのRun Task関連付け
resource "tfe_workspace_run_task" "validator" {
  workspace_id      = tfe_workspace.example.id
  task_id           = tfe_organization_run_task.validator.id
  enforcement_level = "advisory"
  stages            = ["post_plan"]
}
