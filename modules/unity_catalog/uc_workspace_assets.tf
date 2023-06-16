# variables already passed into this module, so not redeclaring in this script
# variable "tags" {}
# variable "prefix_uc" {}


################################
#### Creating UC assets in databricks workspace
################################

#####
##### Creating AWS assets for UC assets
#####

resource "aws_s3_bucket" "external" {
  bucket = "${var.prefix_uc}-external-location"
  acl    = "private"
  versioning {
    enabled = false
  }
  // destroy all objects with bucket destroy
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-external-location"
  })
}

resource "aws_s3_bucket_public_access_block" "external" {
  bucket             = aws_s3_bucket.external.id
  ignore_public_acls = true
  depends_on         = [aws_s3_bucket.external]
}

resource "aws_iam_policy" "external_data_access" {
  // Terraform's "jsonencode" function converts a
  // Terraform expression's result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${aws_s3_bucket.external.id}-access"
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
          aws_s3_bucket.external.arn,
          "${aws_s3_bucket.external.arn}/*"
        ],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-inline-policy-uc-storage-credential"
  })
}

resource "aws_iam_role" "external_data_access" {
  name                = "${var.prefix_uc}-storage-credential-role"
  assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  managed_policy_arns = [aws_iam_policy.external_data_access.arn]
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog-storage-credential-iam-role"
  })
}

#####
##### Creating UC assets in databricks workspace
#####

resource "databricks_storage_credential" "external" {
#   provider = databricks.workspace
  name     = "${var.prefix_uc}-storage-credential"
  aws_iam_role {
    role_arn = aws_iam_role.external_data_access.arn
  }
  comment = "Managed by TF"
}

resource "databricks_external_location" "this" {
#   provider        = databricks.workspace
  name            = "${var.prefix_uc}-external-location"
  url             = "s3://${aws_s3_bucket.external.id}"
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
}