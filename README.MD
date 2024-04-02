# Terraform scripts
* Code currently works as of 2nd April 2024 but with certain workarounds
  * Workarounds needed as a metastore is created by default now with a workspace
* Run a `terraform apply` for `#### Creating Databricks workspace` section first 
  * Uncomment the below sections first
* Then go into DB account console and delete the default metastore created
* Then uncomment `#### Creating UC assets` section and run a `terraform apply`
