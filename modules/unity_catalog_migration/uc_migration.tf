variable prefix {}
variable prefix_uc {}
variable pre_uc_s3_external_bucket_name {}
variable cross_acct_iam_role_name {}
variable instance_profile_name {}
variable tags {}
variable aws_iam_role_passrole_for_uc_json {}

################################
# This script will create all the AWS + Databricks assets to do a U.C migration
# Assets to be created:
# * Instance profile and related AWS assets
# * UC storage credential that points to pre-uc external table s3 location
################################


################################
#### External S3 bucket and creating bucket policy
################################

resource "aws_s3_bucket" "pre_uc_s3_external_bucket" {
  bucket = var.pre_uc_s3_external_bucket_name
  acl    = "private"
  versioning {
    enabled = false
  }
  force_destroy = true
}

data "databricks_aws_bucket_policy" "stuff" {
  bucket = aws_s3_bucket.pre_uc_s3_external_bucket.bucket
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.pre_uc_s3_external_bucket.id
  policy = data.databricks_aws_bucket_policy.stuff.json
}


################################
#### Instance profile creation
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
# adding inline policy since our tf docs did not specify this
resource "aws_iam_role" "role_for_s3_access" {
  name               = var.instance_profile_name
  description        = "Role for instance profile"
  assume_role_policy = data.aws_iam_policy_document.assume_role_for_ec2.json
  inline_policy {
    name = "instance_profile_inline_policy"

    policy = jsonencode(

      {
        "Version" = "2012-10-17",
        "Statement" = [
          {
            "Effect" = "Allow",
            "Action" = [
              "s3:ListBucket"
            ],
            "Resource" = [
              "arn:aws:s3:::${var.pre_uc_s3_external_bucket_name}"
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
              "arn:aws:s3:::${var.pre_uc_s3_external_bucket_name}/*"
            ]
          }
        ]
      }

    )
  }
}

# create pass-role iam policy
data "aws_iam_policy_document" "pass_role_for_s3_access" {
  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.role_for_s3_access.arn]
  }
}

# create in-line policy & attach pass-role policy above to this policy
resource "aws_iam_policy" "pass_role_for_s3_access" {
  name   = "${var.prefix}-inline-policy-instance-profile"
  path   = "/"
  policy = data.aws_iam_policy_document.pass_role_for_s3_access.json
}

# attaching above policy to workspace cross acct iam role
resource "aws_iam_role_policy_attachment" "cross_account" {
  policy_arn = aws_iam_policy.pass_role_for_s3_access.arn
  role       = var.cross_acct_iam_role_name
}

# creating an iam instance profile for the above created instance profile iam role
resource "aws_iam_instance_profile" "shared" {
  name = "${var.prefix}-instance-profile"
  role = aws_iam_role.role_for_s3_access.name
}

# attaching iam role for instance profile to databricks workspace
resource "databricks_instance_profile" "shared" {
#   provider             = databricks.workspace
  instance_profile_arn = aws_iam_instance_profile.shared.arn
}


################################
##### Creating AWS assets for migration demo-purposes
##### Will create an IAM role for a storage credential that points to pre-uc external table s3 location
################################

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
      }
    ]
  })
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-inline-policy-uc-storage-credential-for-pre-uc-s3-location"
  })
}

resource "aws_iam_role" "external_data_access_to_pre_uc_s3_location" {
  name                = "${var.prefix_uc}-storage-credential-role-for-pre-uc-s3-location"
#   assume_role_policy  = data.aws_iam_policy_document.passrole_for_uc.json
  assume_role_policy  = var.aws_iam_role_passrole_for_uc_json
  managed_policy_arns = [aws_iam_policy.external_data_access_to_pre_uc_s3_location.arn]
  tags = merge(var.tags, {
    Name = "${var.prefix_uc}-unity-catalog-storage-credential-for-pre-uc-s3-location-iam-role"
  })
}

#####
##### Creating resultant UC assets in databricks workspace
#####

resource "databricks_storage_credential" "external" {
#   provider = databricks.workspace
  name     = "${var.prefix_uc}-storage-credential-for-pre-uc-s3-location"
  aws_iam_role {
    role_arn = aws_iam_role.external_data_access_to_pre_uc_s3_location.arn
  }
  comment = "Managed by TF"
}

resource "databricks_external_location" "this" {
#   provider        = databricks.workspace
  name            = "${var.prefix_uc}-pre-uc-s3-location-external-location"
  url             = "s3://${aws_s3_bucket.pre_uc_s3_external_bucket.id}"
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
}