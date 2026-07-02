variable "databricks_account_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "cidr_block" {
  type = string
}

variable "region" {
  type = string
}

variable "prefix" {
  type = string
}

################################
#### Creating customer managed vpc
################################

# zone-type filter excludes Local Zones (e.g. ap-southeast-1-han-1a),
# which do not support NAT gateways
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.prefix
  cidr = var.cidr_block
  azs  = data.aws_availability_zones.available.names
  tags = var.tags

  enable_dns_hostnames = true
  enable_nat_gateway   = true
  single_nat_gateway   = true
  create_igw           = true

  public_subnets = [cidrsubnet(var.cidr_block, 3, 0)]
  private_subnets = [cidrsubnet(var.cidr_block, 3, 1),
  cidrsubnet(var.cidr_block, 3, 2)]

  manage_default_security_group = true

  default_security_group_egress = [{
    cidr_blocks = "0.0.0.0/0"
  }]

  default_security_group_ingress = [{
    description = "Allow all internal TCP and UDP"
    self        = true
  }]
}

resource "databricks_mws_networks" "this" {
  account_id         = var.databricks_account_id
  network_name       = "${var.prefix}-network"
  security_group_ids = [module.vpc.default_security_group_id]
  subnet_ids         = module.vpc.private_subnets
  vpc_id             = module.vpc.vpc_id
}


################################
#### Cross-account-iam role
################################

data "databricks_aws_assume_role_policy" "this" {
  external_id = var.databricks_account_id
}

resource "aws_iam_role" "cross_account_role" {
  name               = "${var.prefix}-crossaccount"
  assume_role_policy = data.databricks_aws_assume_role_policy.this.json
  tags               = var.tags
}

data "databricks_aws_crossaccount_policy" "this" {
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.prefix}-policy"
  role   = aws_iam_role.cross_account_role.id
  policy = data.databricks_aws_crossaccount_policy.this.json
}

# custom time_sleep function to wait for aws role to be fully created before attaching it to workspace
# https://github.com/databricks/terraform-provider-databricks/issues/1424#issuecomment-1177870725
resource "time_sleep" "wait_for_cross_account_role" {
  create_duration = "20s"
  depends_on      = [aws_iam_role_policy.this, aws_iam_role.cross_account_role]
}

resource "databricks_mws_credentials" "this" {
  role_arn         = aws_iam_role.cross_account_role.arn
  credentials_name = "${var.prefix}-creds"
  depends_on       = [time_sleep.wait_for_cross_account_role]
}

################################
#### Workspace root bucket
################################

resource "aws_s3_bucket" "root_storage_bucket" {
  bucket        = "${var.prefix}-rootbucket"
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${var.prefix}-rootbucket"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root_storage_bucket" {
  bucket = aws_s3_bucket.root_storage_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "root_storage_bucket" {
  bucket                  = aws_s3_bucket.root_storage_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.root_storage_bucket]
}

data "databricks_aws_bucket_policy" "this" {
  bucket = aws_s3_bucket.root_storage_bucket.bucket
}

resource "aws_s3_bucket_policy" "root_bucket_policy" {
  bucket     = aws_s3_bucket.root_storage_bucket.id
  policy     = data.databricks_aws_bucket_policy.this.json
  depends_on = [aws_s3_bucket_public_access_block.root_storage_bucket]
}

resource "databricks_mws_storage_configurations" "this" {
  account_id                 = var.databricks_account_id
  bucket_name                = aws_s3_bucket.root_storage_bucket.bucket
  storage_configuration_name = "${var.prefix}-storage"
}


################################
#### Creating actual workspace
################################

resource "databricks_mws_workspaces" "this" {
  account_id     = var.databricks_account_id
  aws_region     = var.region
  workspace_name = var.prefix

  credentials_id           = databricks_mws_credentials.this.credentials_id
  storage_configuration_id = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id               = databricks_mws_networks.this.network_id
  # comment out network_id if using databricks managed vpc

  # PAT for the workspace-level provider, created as the workspace creator
  # (your user). The token block is deprecated but is the simplest way to
  # bootstrap workspace auth in the same apply when deploying as a human user
  token {
    comment          = "Terraform PAT"
    lifetime_seconds = 2592000 # 30 days
  }
}

output "databricks_workspace_url" {
  value = databricks_mws_workspaces.this.workspace_url
}

output "databricks_workspace_id" {
  value = databricks_mws_workspaces.this.workspace_id
}

output "databricks_workspace_token" {
  value     = databricks_mws_workspaces.this.token[0].token_value
  sensitive = true
}

output "cross_account_role_name" {
  value = aws_iam_role.cross_account_role.name
}
