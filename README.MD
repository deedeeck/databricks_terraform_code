# Databricks on AWS Terraform scripts

Learning repo that provisions everything needed to get a Databricks workspace on AWS up and running with Unity Catalog assets, in a single `terraform apply`:

* **Workspace** (`modules/workspace`): customer-managed VPC, cross-account IAM role, workspace root S3 bucket, and the E2 workspace itself
* **Unity Catalog assets** (`modules/unity_catalog`): UC storage credential and external location, plus the S3 bucket and IAM role behind them
* **UC migration demo assets** (`modules/unity_catalog_migration`): a "pre-UC" external S3 bucket, an instance profile for the pre-UC access pattern, plus a UC storage credential and external location pointing at the same bucket
* **Clusters** (`modules/clusters`, commented out in `main.tf`): a small UC-enabled test cluster

## Prerequisites

* Terraform >= 1.5
* The Databricks CLI (`brew install databricks`), used to authenticate terraform as your own account admin user via OAuth (username/password basic auth is end-of-life)
* AWS credentials, either in `terraform.tfvars` or in the environment (see setup below)

### AWS credentials setup

Pick one:

* **terraform.tfvars (simplest)**: fill in `aws_access_key` and `aws_secret_key` in `terraform.tfvars`. The file is gitignored so the keys stay out of the repo.
* **Credentials file**: leave the tfvars keys blank, run `aws configure` once and enter your access key, secret key and region. This writes to `~/.aws/credentials` and Terraform picks it up automatically. For multiple accounts, use `aws configure --profile <name>` and select it with `export AWS_PROFILE=<name>` before running terraform.
* **Environment variables (per terminal session)**: leave the tfvars keys blank and export before running terraform:

  ```bash
  export AWS_ACCESS_KEY_ID="AKIA..."
  export AWS_SECRET_ACCESS_KEY="..."
  ```

### Databricks authentication setup

Terraform deploys as **your account admin user** through a Databricks CLI OAuth profile. Log in once (opens a browser):

```bash
databricks auth login --host https://accounts.cloud.databricks.com --account-id <account-id>
```

When prompted for a profile name, use `ACCOUNT` (or set whatever name you chose as `databricks_cli_profile` in `terraform.tfvars`). The OAuth token refreshes automatically; if it fully expires after long inactivity, just run the same command again.

The workspace-level provider uses a 30-day PAT that the workspace creates for your user during the apply, so no extra login is needed for the workspace.

## Usage

1. Fill in the values in `terraform.tfvars` (gitignored, safe for secrets)
2. `terraform init`
3. `terraform apply`

Because your user creates the workspace, you are automatically a workspace admin and the owner of the UC objects, everything is visible in the workspace UI.

## Notes (updated Jul 2026)

* Databricks now automatically creates and assigns a regional metastore when the workspace is created, so this repo no longer creates its own metastore. The old workaround (staged applies + manually deleting the default metastore in the account console) is gone.
* Providers were bumped: `databricks/databricks ~> 1.119`, `hashicorp/aws ~> 6.0`, VPC module `~> 6.0`. This required replacing the removed `aws_s3_bucket` inline `acl`/`versioning` arguments and the removed `aws_iam_role` `managed_policy_arns`/`inline_policy` arguments with standalone resources.
* Terraform runs as your own user: the account-level provider uses a databricks CLI OAuth profile, and the workspace-level provider uses the PAT from the (deprecated but functional) `token {}` block, created for your user with the workspace.
