# Databricks on AWS Terraform scripts

Learning repo that pre-creates an environment for **practicing a Unity Catalog migration**: a workspace with both the legacy hive_metastore world (data on S3 accessed via an instance profile) and the UC world (storage credentials + external locations) side by side, so you can walk through upgrading legacy tables to UC hands-on. Everything deploys in a single `terraform apply`:

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

## Simulating a UC migration

This is the point of the repo. After the apply, the environment maps to the two eras of a migration:

| Terraform asset | Role in the migration story |
|---|---|
| `<prefix>-instance-profile` | Legacy (pre-UC) access: how clusters reached S3 before Unity Catalog |
| `s3://<prefix>-pre-uc-external-s3-bucket` | The "legacy data" bucket where hive_metastore tables live |
| `<prefix_uc>-pre-uc-s3-location-external-location` | UC-era access to that same bucket, the prerequisite for upgrading its tables to UC |
| `<prefix_uc>-external-location` | A fresh UC-native location for net-new data after the migration |

### Step 1 : create the legacy world

Create a cluster with **no isolation shared / legacy access mode** and attach the instance profile (`<prefix>-instance-profile`) under the cluster's instance profile setting. On it, register an external table in hive_metastore backed by the pre-UC bucket:

```sql
CREATE SCHEMA IF NOT EXISTS hive_metastore.legacy_db;

CREATE TABLE hive_metastore.legacy_db.trips
LOCATION 's3://<prefix>-pre-uc-external-s3-bucket/trips'
AS SELECT id, id % 10 AS zone, rand() * 100 AS fare FROM range(100000);
```

This is the "customer starting point": data in S3, table registered only in hive_metastore, access via instance profile.

### Step 2 : migrate the table to UC

The UC external location covering the pre-UC bucket already exists (terraform created it), which is exactly what `SYNC` needs. From a UC-enabled cluster or SQL warehouse:

```sql
CREATE CATALOG IF NOT EXISTS migrated;
CREATE SCHEMA IF NOT EXISTS migrated.legacy_db;

SYNC TABLE migrated.legacy_db.trips FROM hive_metastore.legacy_db.trips;
```

`SYNC` upgrades the external table in place: the data stays where it is in S3, and the table becomes a UC external table governed through the external location instead of the instance profile. Alternatives to practice: the **Upgrade wizard** in Catalog Explorer (right-click a hive_metastore schema), `SYNC SCHEMA` for bulk upgrades, or `CREATE TABLE ... AS SELECT` / `DEEP CLONE` into a UC **managed** table when you want to relocate the data rather than upgrade in place.

### Step 3 : validate and cut over

* Query `migrated.legacy_db.trips` from a UC cluster (standard access mode, **no instance profile attached**) to prove access now flows through the storage credential
* Compare row counts between the HMS and UC tables
* In a real migration you would now repoint jobs/queries to the UC table and eventually drop the HMS entry (the data is untouched since the table is external)

For real-world, large-scale migrations, look at [UCX](https://github.com/databrickslabs/ucx), the Databricks Labs migration toolkit; this repo is the hand-rolled version of what it automates, at learning scale.

## Notes (updated Jul 2026)

* Databricks now automatically creates and assigns a regional metastore when the workspace is created, so this repo no longer creates its own metastore. The old workaround (staged applies + manually deleting the default metastore in the account console) is gone.
* Providers were bumped: `databricks/databricks ~> 1.119`, `hashicorp/aws ~> 6.0`, VPC module `~> 6.0`. This required replacing the removed `aws_s3_bucket` inline `acl`/`versioning` arguments and the removed `aws_iam_role` `managed_policy_arns`/`inline_policy` arguments with standalone resources.
* Terraform runs as your own user: the account-level provider uses a databricks CLI OAuth profile, and the workspace-level provider uses the PAT from the (deprecated but functional) `token {}` block, created for your user with the workspace.
