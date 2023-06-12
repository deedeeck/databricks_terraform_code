variable "cluster_name" {}
# variable "cluster_autotermination_minutes" {}
# variable "cluster_num_workers" {}
# variable "cluster_data_security_mode" {}

resource "databricks_cluster" "this" {
  cluster_name            = var.cluster_name
  node_type_id            = "i3.xlarge"
  spark_version           = "12.2.x-scala2.12"
  autotermination_minutes = "10"
  num_workers             = "1"
}

output "cluster_url" {
  value = databricks_cluster.this.url
}
