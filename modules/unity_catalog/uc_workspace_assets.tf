################################
#### Creating UC assets in databricks workspace
################################

# wait for the IAM role to propagate, otherwise storage credential
# validation can fail right after role creation
resource "time_sleep" "wait_for_storage_credential_role" {
  create_duration = "30s"
  depends_on = [
    aws_iam_role.external_data_access,
    aws_iam_role_policy_attachment.external_data_access
  ]
}

resource "databricks_storage_credential" "external" {
  name = "${var.prefix_uc}-storage-credential"
  aws_iam_role {
    role_arn = aws_iam_role.external_data_access.arn
  }
  comment       = "Managed by TF"
  force_destroy = true
  depends_on    = [time_sleep.wait_for_storage_credential_role]
}

# force_destroy allows terraform destroy to remove the location even when
# catalogs/tables were created on it (fine for a demo environment)
resource "databricks_external_location" "this" {
  name            = "${var.prefix_uc}-external-location"
  url             = "s3://${aws_s3_bucket.external.id}"
  credential_name = databricks_storage_credential.external.id
  comment         = "Managed by TF"
  force_destroy   = true
}
