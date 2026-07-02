variable "databricks_account_id" {
  description = "Databricks account ID, found in the account console"
  type        = string
  default     = "xxx"
}

variable "databricks_cli_profile" {
  description = "Name of the databricks CLI profile for the account console, created with: databricks auth login --host https://accounts.cloud.databricks.com --account-id <account-id>"
  type        = string
  default     = "ACCOUNT"
}

variable "aws_account_id" {
  description = "AWS account ID where all resources will be created"
  type        = string
  default     = "xxx"
}

variable "aws_access_key" {
  description = "AWS access key ID. Leave blank to use the environment (AWS_PROFILE / SSO or env vars) instead"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aws_secret_key" {
  description = "AWS secret access key. Leave blank to use the environment instead"
  type        = string
  sensitive   = true
  default     = ""
}

variable "prefix" {
  description = "Prefix for workspace-related resource names"
  type        = string
  default     = "xxx"
}

variable "prefix_uc" {
  description = "Prefix for Unity Catalog related resource names"
  type        = string
  default     = "xxx"
}

variable "tags" {
  description = "Tags applied to all AWS resources"
  type        = map(string)
  default     = {}
}

variable "cidr_block" {
  description = "CIDR block for the customer-managed VPC"
  type        = string
  default     = "10.4.0.0/16"
}

variable "region" {
  description = "AWS region for the workspace and all AWS resources"
  type        = string
  default     = "ap-southeast-1"
}
