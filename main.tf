terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "=1.17.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.15.0"
    }
  }
}

################################
#### Creating Databricks workspace
################################

provider "aws" {
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "databricks" {
  alias    = "mws"
  host     = "https://accounts.cloud.databricks.com"
  username = var.databricks_account_username
  password = var.databricks_account_password
}

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

# creating databricks workspace provider after creating workspace
provider "databricks" {
  alias = "workspace"
  host  = module.workspace.databricks_workspace_url
  token = module.workspace.databricks_workspace_token
}

################################
#### Creating UC assets
################################

module "uc_assets" {
  source                = "./modules/unity_catalog"
  aws_account_id        = var.aws_account_id
  databricks_account_id = var.databricks_account_id
  tags                  = var.tags
  prefix_uc             = var.prefix_uc
  workspace_id          = module.workspace.databricks_workspace_id

  providers = {
    databricks = databricks.workspace
    aws        = aws
  }

}

################################
#### Creating UC migration assets
################################

module "uc_migration" {
  source                            = "./modules/unity_catalog_migration"
  prefix                            = var.prefix
  prefix_uc                         = var.prefix_uc
  pre_uc_s3_external_bucket_name    = "${var.prefix}-pre-uc-external-s3-bucket"
  cross_acct_iam_role_name          = "${var.prefix}-crossaccount"
  instance_profile_name             = "${var.prefix}-instance-profile"
  tags                              = var.tags
  aws_iam_role_passrole_for_uc_json = module.uc_assets.aws_iam_role_passrole_for_uc_json

  providers = {
    databricks = databricks.workspace
    aws        = aws
  }

}

################################
#### Creating workspace assets
################################

# module "clusters" {
#   source       = "./modules/clusters"
#   cluster_name = "test-terraform cluster"
#   # cluster_autotermination_minutes = "10"
#   # cluster_num_workers = "1"
#   # data_security_mode = "NONE"

#   providers = {
#     databricks = databricks.workspace
#   }
# }

# output "clusters_url" {
#   value = module.clusters.cluster_url
# }