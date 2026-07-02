variable "cluster_name" {
  type = string
}

# look up latest LTS runtime and smallest node type instead of hardcoding
data "databricks_spark_version" "latest_lts" {
  long_term_support = true
}

data "databricks_node_type" "smallest" {
  local_disk = true
}

resource "databricks_cluster" "this" {
  cluster_name            = var.cluster_name
  node_type_id            = data.databricks_node_type.smallest.id
  spark_version           = data.databricks_spark_version.latest_lts.id
  autotermination_minutes = 10
  num_workers             = 1
  data_security_mode      = "USER_ISOLATION" # standard access mode, UC enabled
}

output "cluster_url" {
  value = databricks_cluster.this.url
}
