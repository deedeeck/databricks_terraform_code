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
  region = var.region
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
  source       = "./modules/workspace"
  prefix = "yh-terraform-modules-test1"
  databricks_account_id = var.databricks_account_id
  region = var.region
  tags = var.tags
  cidr_block = var.cidr_block

  providers = {
    databricks = databricks.mws
    aws = aws
  }

}


################################
#### Creating UC assets
################################


################################
#### Creating workspace assets
################################

# provider "databricks" {
#   alias = "workspace"
#   host  = module.workspace.databricks_workspace_url
#   token = module.workspace.databricks_workspace_token
# }

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

# output "ba" {
#   value = module.clusters.cluster_url
# }