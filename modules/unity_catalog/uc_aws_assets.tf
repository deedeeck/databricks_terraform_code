variable aws_account_id {}
variable databricks_account_id {}
variable "tags" {}
variable "prefix_uc" {}
variable "workspace_id" {}


################################
#### Creating AWS assets for UC
################################

resource "aws_s3_bucket" "metastore" {
  bucket = "${var.prefix_uc}-metastore"
  acl    = "private"
  versioning {
    enabled = false
  }
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-metastore"
  })
}

resource "aws_s3_bucket_public_access_block" "metastore" {
  bucket                  = aws_s3_bucket.metastore.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.metastore]
}

data "aws_iam_policy_document" "passrole_for_uc" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"]
      type        = "AWS"
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
  statement {
    sid     = "ExplicitSelfRoleAssumption"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.aws_account_id}:role/${var.prefix_uc}-uc-access"]
    }
  }
}

resource "aws_iam_policy" "unity_metastore" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.prefix_uc}-databricks-unity-metastore"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          aws_s3_bucket.metastore.arn,
          "${aws_s3_bucket.metastore.arn}/*"
        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog IAM policy"
  })
}

// Required, in case https://docs.databricks.com/data/databricks-datasets.html are needed
resource "aws_iam_policy" "sample_data" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.prefix_uc}-databricks-sample-data"
    Statement = [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          "arn:aws:s3:::databricks-datasets-oregon/*",
          "arn:aws:s3:::databricks-datasets-oregon"

        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog IAM policy"
  })
}

resource "aws_iam_role" "metastore_data_access" {
  name                = "${var.prefix_uc}-metastore-iam-role"
  assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  managed_policy_arns = [aws_iam_policy.unity_metastore.arn, aws_iam_policy.sample_data.arn]
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog-metastore-iam-role"
  })
}


################################
#### Creating UC metastore and linking it to workspace
################################

resource "databricks_metastore" "this" {
  # provider     = databricks.workspace
  name         = "yh-metastore-terraform"
  storage_root = "s3://${aws_s3_bucket.metastore.id}/metastore"
  #   owner         = var.unity_admin_group
  #   owner         = "xxx"
  force_destroy = true
}


# custom time_sleep function to wait for metastore to be created as there seems to be a race condition
# source : https://databricks.slack.com/archives/C029UBNLMGX/p1678154207183369
# yh comments : time sleep does not seem to help here
resource "time_sleep" "wait_for_metastore_creation" {
  create_duration = "60s"
  depends_on      = [databricks_metastore.this]
}

resource "databricks_metastore_data_access" "this" {
  # provider     = databricks.workspace
  metastore_id = databricks_metastore.this.id
  name         = aws_iam_role.metastore_data_access.name
  aws_iam_role {
    role_arn = aws_iam_role.metastore_data_access.arn
  }
  is_default = true

  depends_on = [
    databricks_metastore.this
  ]
}

resource "databricks_metastore_assignment" "default_metastore" {
  # provider = databricks.workspace
  workspace_id         = var.workspace_id
  metastore_id         = databricks_metastore.this.id
  default_catalog_name = "hive_metastore"
}