variable "aws_account_id" {
  type = string
}

variable "databricks_account_id" {
  type = string
}

variable "prefix" {
  type = string
}

variable "prefix_uc" {
  type = string
}

variable "cross_acct_iam_role_name" {
  type = string
}

variable "pre_uc_s3_external_bucket_name" {
  type = string
}

variable "tags" {
  type = map(string)
}

locals {
  pre_uc_storage_credential_role_name = "${var.prefix_uc}-storage-credential-role-for-pre-uc-s3-location"
}

################################
# This script will create all the AWS + Databricks assets to do a U.C migration
# Assets to be created:
# * "pre-UC" external S3 bucket that simulates data created before UC
# * Instance profile and related AWS assets (the pre-UC access pattern)
# * UC storage credential + external location that point to that bucket
################################


################################
#### External S3 bucket
################################

resource "aws_s3_bucket" "pre_uc_s3_external_bucket" {
  bucket        = var.pre_uc_s3_external_bucket_name
  force_destroy = true
  tags = merge(var.tags, {
    Name = var.pre_uc_s3_external_bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "pre_uc_s3_external_bucket" {
  bucket                  = aws_s3_bucket.pre_uc_s3_external_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket.pre_uc_s3_external_bucket]
}


################################
#### Instance profile creation (pre-UC access pattern)
################################

# create assume-role iam policy
data "aws_iam_policy_document" "assume_role_for_ec2" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

# create instance profile iam role & attach assume-role policy above to this role
resource "aws_iam_role" "role_for_s3_access" {
  name               = "${var.prefix}-instance-profile"
  description        = "Role for instance profile"
  assume_role_policy = data.aws_iam_policy_document.assume_role_for_ec2.json
  tags               = var.tags
}

# inline_policy on aws_iam_role was removed in aws provider v6,
# a standalone aws_iam_role_policy is used instead
resource "aws_iam_role_policy" "instance_profile_s3_access" {
  name = "instance_profile_inline_policy"
  role = aws_iam_role.role_for_s3_access.id

  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Action" = [
          "s3:ListBucket"
        ],
        "Resource" = [
          aws_s3_bucket.pre_uc_s3_external_bucket.arn
        ]
      },
      {
        "Effect" = "Allow",
        "Action" = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObjectAcl"
        ],
        "Resource" = [
          "${aws_s3_bucket.pre_uc_s3_external_bucket.arn}/*"
        ]
      }
    ]
  })
}

# create pass-role iam policy
data "aws_iam_policy_document" "pass_role_for_s3_access" {
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.role_for_s3_access.arn]
  }
}

resource "aws_iam_policy" "pass_role_for_s3_access" {
  name   = "${var.prefix}-policy-pass-role-instance-profile"
  path   = "/"
  policy = data.aws_iam_policy_document.pass_role_for_s3_access.json
}

# attaching above policy to workspace cross acct iam role, so the workspace
# is allowed to launch clusters with this instance profile
resource "aws_iam_role_policy_attachment" "cross_account" {
  policy_arn = aws_iam_policy.pass_role_for_s3_access.arn
  role       = var.cross_acct_iam_role_name
}

# creating an iam instance profile for the above created instance profile iam role
resource "aws_iam_instance_profile" "shared" {
  name = "${var.prefix}-instance-profile"
  role = aws_iam_role.role_for_s3_access.name
}

# wait for IAM propagation, databricks validates the pass-role setup
# when registering the instance profile
resource "time_sleep" "wait_for_instance_profile" {
  create_duration = "30s"
  depends_on = [
    aws_iam_instance_profile.shared,
    aws_iam_role_policy_attachment.cross_account
  ]
}

# attaching iam role for instance profile to databricks workspace
resource "databricks_instance_profile" "shared" {
  instance_profile_arn = aws_iam_instance_profile.shared.arn
  depends_on           = [time_sleep.wait_for_instance_profile]
}


################################
##### Creating AWS assets for migration demo-purposes
##### IAM role for a storage credential that points to pre-uc external table s3 location
################################

data "databricks_aws_unity_catalog_assume_role_policy" "pre_uc" {
  aws_account_id = var.aws_account_id
  role_name      = local.pre_uc_storage_credential_role_name
  external_id    = var.databricks_account_id
}

resource "aws_iam_policy" "external_data_access_to_pre_uc_s3_location" {
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${aws_s3_bucket.pre_uc_s3_external_bucket.id}-access"
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
          aws_s3_bucket.pre_uc_s3_external_bucket.arn,
          "${aws_s3_bucket.pre_uc_s3_external_bucket.arn}/*"
        ],
        "Effect" : "Allow"
      },
      {
        # UC requires the role to be self-assuming : it must be able to
        # call sts:AssumeRole on itself, in addition to the trust policy
        "Action" : ["sts:AssumeRole"],
        "Resource" : ["arn:aws:iam::${var.aws_account_id}:role/${local.pre_uc_storage_credential_role_name}"],
        "Effect" : "Allow"
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-policy-uc-storage-credential-for-pre-uc-s3-location"
  })
}

resource "aws_iam_role" "external_data_access_to_pre_uc_s3_location" {
  name               = local.pre_uc_storage_credential_role_name
  assume_role_policy = data.databricks_aws_unity_catalog_assume_role_policy.pre_uc.json
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog-storage-credential-for-pre-uc-s3-location-iam-role"
  })
}

resource "aws_iam_role_policy_attachment" "external_data_access_to_pre_uc_s3_location" {
  role       = aws_iam_role.external_data_access_to_pre_uc_s3_location.name
  policy_arn = aws_iam_policy.external_data_access_to_pre_uc_s3_location.arn
}

#####
##### Creating resultant UC assets in databricks workspace
#####

# wait for the IAM role to propagate, otherwise storage credential
# validation can fail right after role creation
resource "time_sleep" "wait_for_pre_uc_storage_credential_role" {
  create_duration = "30s"
  depends_on = [
    aws_iam_role.external_data_access_to_pre_uc_s3_location,
    aws_iam_role_policy_attachment.external_data_access_to_pre_uc_s3_location
  ]
}

resource "databricks_storage_credential" "external" {
  name = "${var.prefix_uc}-storage-credential-for-pre-uc-s3-location"
  aws_iam_role {
    role_arn = aws_iam_role.external_data_access_to_pre_uc_s3_location.arn
  }
  comment       = "Managed by TF"
  force_destroy = true
  depends_on    = [time_sleep.wait_for_pre_uc_storage_credential_role]
}

# force_destroy allows terraform destroy to remove the location even when
# catalogs/tables were created on it (fine for a demo environment)
resource "databricks_external_location" "this" {
  name            = "${var.prefix_uc}-pre-uc-s3-location-external-location"
  url             = "s3://${aws_s3_bucket.pre_uc_s3_external_bucket.id}"
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
  force_destroy   = true
}
