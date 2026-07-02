terraform {
  required_version = ">= 1.5"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.119"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

################################
#### Providers
################################

# AWS credentials can be set in terraform.tfvars (aws_access_key / aws_secret_key),
# or left blank there to fall back to the environment (AWS_PROFILE / SSO, or
# AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)
provider "aws" {
  region     = var.region
  access_key = var.aws_access_key != "" ? var.aws_access_key : null
  secret_key = var.aws_secret_key != "" ? var.aws_secret_key : null
}

# Account-level provider, authenticates as YOUR user through a databricks CLI
# OAuth profile (username/password basic auth is end-of-life). Create the
# profile once with:
#   databricks auth login --host https://accounts.cloud.databricks.com --account-id <account-id>
provider "databricks" {
  alias      = "mws"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
  profile    = var.databricks_cli_profile
}

################################
#### Creating Databricks workspace
################################

module "workspace" {
  source                = "./modules/workspace"
  prefix                = var.prefix
  databricks_account_id = var.databricks_account_id
  region                = var.region
  tags                  = var.tags
  cidr_block            = var.cidr_block

  providers = {
    databricks = databricks.mws
    aws        = aws
  }
}

# Workspace-level provider, uses the PAT created together with the workspace.
# The workspace is created by your user, which makes you a workspace admin
# and the owner of all UC objects created below
provider "databricks" {
  alias = "workspace"
  host  = module.workspace.databricks_workspace_url
  token = module.workspace.databricks_workspace_token
}

################################
#### Creating UC assets
################################

# A metastore is automatically created and assigned to the workspace by
# Databricks, so this module only creates the storage credential and
# external location (plus their AWS IAM/S3 assets)

module "uc_assets" {
  source                = "./modules/unity_catalog"
  aws_account_id        = var.aws_account_id
  databricks_account_id = var.databricks_account_id
  tags                  = var.tags
  prefix_uc             = var.prefix_uc

  providers = {
    databricks = databricks.workspace
    aws        = aws
  }

  depends_on = [module.workspace]
}

################################
#### Creating UC migration assets
################################

module "uc_migration" {
  source                         = "./modules/unity_catalog_migration"
  aws_account_id                 = var.aws_account_id
  databricks_account_id          = var.databricks_account_id
  prefix                         = var.prefix
  prefix_uc                      = var.prefix_uc
  pre_uc_s3_external_bucket_name = "${var.prefix}-pre-uc-external-s3-bucket"
  cross_acct_iam_role_name       = module.workspace.cross_account_role_name
  tags                           = var.tags

  providers = {
    databricks = databricks.workspace
    aws        = aws
  }

  depends_on = [module.workspace]
}

################################
#### Creating workspace assets
################################

# module "clusters" {
#   source       = "./modules/clusters"
#   cluster_name = "test-terraform cluster"

#   providers = {
#     databricks = databricks.workspace
#   }
# }

# output "clusters_url" {
#   value = module.clusters.cluster_url
# }

output "databricks_workspace_url" {
  value = module.workspace.databricks_workspace_url
}
