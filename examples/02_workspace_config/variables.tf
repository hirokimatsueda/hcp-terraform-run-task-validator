variable "tfc_organization_name" {
  description = "HCP Terraform organization name"
  type        = string
}

variable "tfc_project_name" {
  description = "HCP Terraform project name"
  type        = string
}

variable "workspace_name" {
  description = "Name of the workspace"
  type        = string
}

variable "working_directory" {
  description = "Working directory for the workspace"
  type        = string
}

variable "vcs_repo_identifier" {
  description = "VCS repository identifier (e.g., 'organization/repository')"
  type        = string
}

variable "vcs_branch" {
  description = "VCS branch name"
  type        = string
  default     = "main"
}

variable "run_task_workspace_name" {
  description = "Name of the workspace containing Run Task resources"
  type        = string
}

variable "github_username_or_organization" {
  description = "Name of the Github user or organization account that installed the app"
  type        = string
}
