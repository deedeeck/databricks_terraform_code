variable "aws_account_id" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "prefix_uc" {
  type = string
}

locals {
  storage_credential_role_name = "${var.prefix_uc}-storage-credential-role"
}

################################
#### Creating AWS assets for UC
################################

# Note : the metastore itself is no longer created here. Databricks
# automatically creates and assigns a regional metastore when the
# workspace is created, so only the storage credential / external
# location assets are needed.

resource "aws_s3_bucket" "external" {
  bucket = "${var.prefix_uc}-external-location"
  // destroy all objects with bucket destroy
  force_destroy = true
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-external-location"
  })
}

resource "aws_s3_bucket_public_access_block" "external" {
  bucket                  = aws_s3_bucket.external.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.external]
}

# provider-maintained trust policy : UC master role + self-assume,
# replaces the previous hand-rolled policy with a hardcoded UC role arn
data "databricks_aws_unity_catalog_assume_role_policy" "this" {
  aws_account_id = var.aws_account_id
  role_name      = local.storage_credential_role_name
  external_id    = var.databricks_account_id
}

resource "aws_iam_policy" "external_data_access" {
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
      },
      {
        # UC requires the role to be self-assuming : it must be able to
        # call sts:AssumeRole on itself, in addition to the trust policy
        "Action" : ["sts:AssumeRole"],
        "Resource" : ["arn:aws:iam::${var.aws_account_id}:role/${local.storage_credential_role_name}"],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-policy-uc-storage-credential"
  })
}

resource "aws_iam_role" "external_data_access" {
  name               = local.storage_credential_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.this.json
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog-storage-credential-iam-role"
  })
}

# managed_policy_arns on aws_iam_role was removed in aws provider v6,
# policies are now attached with standalone attachment resources
resource "aws_iam_role_policy_attachment" "external_data_access" {
  role       = aws_iam_role.external_data_access.name
  policy_arn = aws_iam_policy.external_data_access.arn
}
